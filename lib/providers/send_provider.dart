library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/campaign_summary.dart';
import '../models/delivery_record.dart';
import '../models/recipient.dart';
import '../models/send_job.dart';
import '../repositories/reports_repository.dart';
import '../services/sms_channel.dart';
import 'campaigns_provider.dart';
import 'inbox_provider.dart';
import 'settings_provider.dart';

// Shared repository provider (also imported by reports_provider)
final reportsRepositoryProvider = Provider<ReportsRepository>(
  (_) => ReportsRepository(),
);

class SendNotifier extends Notifier<SendJob> {
  bool _cancelled = false;

  @override
  SendJob build() => SendJob(
        id: const Uuid().v4(),
        recipients: const [],
        message: '',
      );

  /// Sends [message] to each recipient using the device's SMS.
  /// Runs fully async – the user may navigate away; sending continues.
  Future<void> startSend({
    required List<Recipient> recipients,
    required String message,
    String? groupName,
  }) async {
    _cancelled = false;
    final jobId = const Uuid().v4();
    final sentAt = DateTime.now();
    state = SendJob(
      id: jobId,
      recipients: recipients,
      message: message,
      status: JobStatus.running,
    );

    // Save campaign record immediately so it appears in history even if
    // the user force-quits before completion.
    final campaign = CampaignSummary(
      id: jobId,
      message: message,
      numbers: recipients.map((r) => r.e164).toList(),
      sentAt: sentAt,
      groupName: groupName,
    );
    try {
      await ref.read(campaignsRepositoryProvider).save(campaign);
    } catch (_) {}

    int sent = 0;
    int failed = 0;

    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final subscriptionId = settingsRepo.selectedSimSubscriptionId;
      final delayMs = settingsRepo.interSmsDelayMs;
      final batchSize = settingsRepo.batchSize;
      final reportsRepo = ref.read(reportsRepositoryProvider);

      for (int i = 0; i < recipients.length; i++) {
        if (_cancelled) break;

        final r = recipients[i];
        final body = _applyMergeTags(message, r);

        bool ok = false;
        try {
          ok = await SmsChannel.sendSms(
            number: r.e164,
            message: body,
            subscriptionId: subscriptionId >= 0 ? subscriptionId : null,
          );
        } catch (_) {
          ok = false;
        }

        // Save each record immediately so reports stay live.
        final record = DeliveryRecord(
          jobId: jobId,
          number: r.e164,
          messageBody: body,
          status: ok ? DeliveryStatus.sent : DeliveryStatus.failed,
          sentAt: DateTime.now(),
          errorMessage: ok ? null : 'SMS send failed',
        );
        try { await reportsRepo.save(record); } catch (_) {}

        if (ok) { sent++; } else { failed++; }

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
    } catch (e) {
      debugPrint('Send loop error: $e');
    }

    // Update campaign with final counts.
    try {
      await ref.read(campaignsRepositoryProvider).update(
            campaign.copyWith(sent: sent, failed: failed),
          );
      ref.read(campaignsProvider.notifier).refresh();
    } catch (_) {}

    // Refresh inbox threads (sent messages now in content provider).
    try { ref.read(inboxProvider.notifier).loadThreads(); } catch (_) {}

    try {
      state = state.copyWith(
        status: _cancelled ? JobStatus.cancelled : JobStatus.done,
      );
    } catch (_) {}
  }

  void cancel() => _cancelled = true;

  void reset() {
    _cancelled = false;
    state = SendJob(
      id: const Uuid().v4(),
      recipients: const [],
      message: '',
    );
  }

  String _applyMergeTags(String msg, Recipient r) {
    String body = msg;
    r.mergeTags.forEach((k, v) => body = body.replaceAll('{{$k}}', v));
    if (r.displayName != null) {
      body = body.replaceAll('{{name}}', r.displayName!);
    }
    return body;
  }
}

final sendProvider = NotifierProvider<SendNotifier, SendJob>(
  SendNotifier.new,
);
