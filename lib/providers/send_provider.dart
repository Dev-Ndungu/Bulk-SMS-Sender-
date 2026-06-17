library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/campaign_summary.dart';
import '../models/delivery_record.dart';
import '../models/recipient.dart';
import '../models/send_job.dart';
import '../services/bulk_send_sync_service.dart';
import '../services/sms_channel.dart';
import 'campaigns_provider.dart';
import 'inbox_provider.dart';
import 'reports_repository_provider.dart';
import 'reports_provider.dart' as reports;
import 'settings_provider.dart';

class SendNotifier extends Notifier<SendJob> {
  bool _cancelled = false;
  Timer? _pollTimer;
  String? _activeJobId;
  int _syncedRecordCount = 0;

  @override
  SendJob build() {
    ref.onDispose(() => _pollTimer?.cancel());
    return SendJob(
      id: const Uuid().v4(),
      recipients: const [],
      message: '',
    );
  }

  /// Sends [message] to each recipient using a native background bulk job.
  /// Runs fully async – the user may navigate away; sending continues.
  Future<void> startSend({
    required List<Recipient> recipients,
    required String message,
    String? groupName,
  }) async {
    final safeRecipients = _dedupeRecipients(recipients);
    final cleanMessage = message.trim();
    if (safeRecipients.isEmpty || cleanMessage.isEmpty) {
      state = SendJob(
        id: const Uuid().v4(),
        recipients: safeRecipients,
        message: cleanMessage,
      );
      return;
    }

    _cancelled = false;
    _pollTimer?.cancel();

    final jobId = const Uuid().v4();
    final sentAt = DateTime.now();
    _activeJobId = jobId;
    _syncedRecordCount = 0;

    state = SendJob(
      id: jobId,
      recipients: safeRecipients,
      message: cleanMessage,
      status: JobStatus.running,
    );

    final campaign = CampaignSummary(
      id: jobId,
      message: cleanMessage,
      numbers: safeRecipients.map((r) => r.e164).toList(growable: false),
      sentAt: sentAt,
      groupName: groupName,
    );
    try {
      await ref.read(campaignsRepositoryProvider).save(campaign);
    } catch (_) {}

    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final subscriptionId = settingsRepo.selectedSimSubscriptionId;
      final delayMs = settingsRepo.interSmsDelayMs.clamp(0, 5000).toInt();
      final batchSize = settingsRepo.batchSize.clamp(1, 500).toInt();

      final started = await SmsChannel.startBulkSend(
        jobId: jobId,
        recipients: safeRecipients
            .map(
              (r) => {
                'number': r.e164,
                'displayName': r.displayName,
                'mergeTags': r.mergeTags,
              },
            )
            .toList(growable: false),
        message: cleanMessage,
        subscriptionId: subscriptionId >= 0 ? subscriptionId : null,
        groupName: groupName,
        delayMs: delayMs,
        batchSize: batchSize,
      );

      if (started) {
        _startPolling(jobId);
        return;
      }
    } catch (e) {
      debugPrint('Native bulk send error: $e');
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _markNativeStartFailed(
        jobId: jobId,
        recipients: safeRecipients,
        message: cleanMessage,
        groupName: groupName,
        sentAt: sentAt,
      );
      return;
    }

    await _legacySendLoop(
      jobId: jobId,
      recipients: safeRecipients,
      message: cleanMessage,
      groupName: groupName,
    );
  }

  Future<void> _markNativeStartFailed({
    required String jobId,
    required List<Recipient> recipients,
    required String message,
    required String? groupName,
    required DateTime sentAt,
  }) async {
    try {
      await ref.read(campaignsRepositoryProvider).update(
            CampaignSummary(
              id: jobId,
              message: message,
              numbers: recipients.map((r) => r.e164).toList(growable: false),
              sentAt: sentAt,
              sent: 0,
              failed: recipients.length,
              groupName: groupName,
            ),
          );
      ref.read(campaignsProvider.notifier).refresh();
    } catch (_) {}

    try {
      state = state.copyWith(
        failed: recipients.length,
        status: JobStatus.done,
      );
    } catch (_) {}
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_cancelled || _activeJobId != jobId) {
        timer.cancel();
        return;
      }

      final BulkSendJobSnapshot? snapshot;
      try {
        snapshot = await BulkSendSyncService.fetchJob(
          jobId,
          recordsFrom: _syncedRecordCount,
        );
      } catch (e) {
        debugPrint('Bulk send polling error: $e');
        return;
      }
      if (snapshot == null) return;

      if (snapshot.records.isNotEmpty) {
        await BulkSendSyncService.persistSnapshot(snapshot);
        _syncedRecordCount += snapshot.records.length;
        ref.read(campaignsProvider.notifier).refresh();
        ref.read(reports.reportsProvider.notifier).refresh();
      }

      try {
        state = state.copyWith(sent: snapshot.sent, failed: snapshot.failed);
      } catch (_) {}

      if (snapshot.isComplete) {
        await _finalizeFromSnapshot(snapshot);
        timer.cancel();
      }
    });
  }

  Future<void> _finalizeFromSnapshot(BulkSendJobSnapshot snapshot) async {
    if (_activeJobId != snapshot.jobId) return;

    if (snapshot.records.isNotEmpty) {
      await BulkSendSyncService.persistSnapshot(snapshot);
      _syncedRecordCount += snapshot.records.length;
    } else {
      await ref.read(campaignsRepositoryProvider).save(snapshot.toCampaignSummary());
    }

    ref.read(campaignsProvider.notifier).refresh();
    ref.read(reports.reportsProvider.notifier).refresh();
    try {
      ref.read(inboxProvider.notifier).loadThreads();
    } catch (_) {}

    try {
      state = state.copyWith(
        sent: snapshot.sent,
        failed: snapshot.failed,
        status: _cancelled ? JobStatus.cancelled : JobStatus.done,
      );
    } catch (_) {}

    if (snapshot.isComplete) {
      unawaited(SmsChannel.clearBulkSendJob(snapshot.jobId));
    }
  }

  Future<void> _legacySendLoop({
    required String jobId,
    required List<Recipient> recipients,
    required String message,
    required String? groupName,
  }) async {
    final reportsRepo = ref.read(reportsRepositoryProvider);
    var sent = 0;
    var failed = 0;
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final subscriptionId = settingsRepo.selectedSimSubscriptionId;
    final delayMs = settingsRepo.interSmsDelayMs.clamp(0, 5000).toInt();
    final batchSize = settingsRepo.batchSize.clamp(1, 500).toInt();

    for (int i = 0; i < recipients.length; i++) {
      if (_cancelled) break;

      final recipient = recipients[i];
      final body = _applyMergeTags(message, recipient);
      var ok = false;
      try {
        ok = await SmsChannel.sendSms(
          number: recipient.e164,
          message: body,
          subscriptionId: subscriptionId >= 0 ? subscriptionId : null,
        );
      } catch (_) {
        ok = false;
      }

      final record = DeliveryRecord(
        jobId: jobId,
        number: recipient.e164,
        messageBody: body,
        status: ok ? DeliveryStatus.sent : DeliveryStatus.failed,
        sentAt: DateTime.now(),
        errorMessage: ok ? null : 'SMS send failed',
      );
      try {
        await reportsRepo.save(record);
      } catch (_) {}

      if (ok) {
        sent++;
      } else {
        failed++;
      }

      try {
        state = state.copyWith(sent: sent, failed: failed);
      } catch (_) {}

      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      if ((i + 1) % batchSize == 0 && i + 1 < recipients.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    try {
      await ref.read(campaignsRepositoryProvider).update(
            CampaignSummary(
              id: jobId,
              message: message,
              numbers: recipients.map((r) => r.e164).toList(growable: false),
              sentAt: DateTime.now(),
              sent: sent,
              failed: failed,
              groupName: groupName,
            ),
          );
      ref.read(campaignsProvider.notifier).refresh();
    } catch (_) {}

    try {
      ref.read(inboxProvider.notifier).loadThreads();
    } catch (_) {}

    try {
      state = state.copyWith(
        status: _cancelled ? JobStatus.cancelled : JobStatus.done,
      );
    } catch (_) {}
  }

  void cancel() {
    _cancelled = true;
    final jobId = _activeJobId;
    if (jobId != null) {
      unawaited(SmsChannel.cancelBulkSend(jobId));
    }
    _pollTimer?.cancel();
    if (state.status == JobStatus.running) {
      state = state.copyWith(status: JobStatus.cancelled);
    }
  }

  void reset() {
    _cancelled = false;
    _pollTimer?.cancel();
    _activeJobId = null;
    _syncedRecordCount = 0;
    state = SendJob(
      id: const Uuid().v4(),
      recipients: const [],
      message: '',
    );
  }

  String _applyMergeTags(String msg, Recipient r) {
    var body = msg;
    r.mergeTags.forEach((k, v) => body = body.replaceAll('{{$k}}', v));
    body = body.replaceAll('{{name}}', r.displayName ?? '');
    body = body.replaceAll('{{phone}}', r.e164);
    return body;
  }

  List<Recipient> _dedupeRecipients(List<Recipient> recipients) {
    final seen = <String>{};
    final cleaned = <Recipient>[];
    for (final recipient in recipients) {
      if (seen.add(recipient.e164)) {
        cleaned.add(recipient);
      }
    }
    return cleaned;
  }
}

final sendProvider = NotifierProvider<SendNotifier, SendJob>(
  SendNotifier.new,
);
