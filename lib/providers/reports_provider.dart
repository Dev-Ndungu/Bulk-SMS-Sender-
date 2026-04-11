library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery_record.dart';
import '../services/sms_channel.dart';
import 'reports_repository_provider.dart';
import 'settings_provider.dart';

class ReportsNotifier extends Notifier<List<DeliveryRecord>> {
  @override
  List<DeliveryRecord> build() =>
      ref.read(reportsRepositoryProvider).getAll();

  void refresh() {
    state = ref.read(reportsRepositoryProvider).getAll();
  }

  Future<void> clearAll() async {
    await ref.read(reportsRepositoryProvider).clearAll();
    state = [];
  }

  /// Re-sends all failed messages for [jobId] using the native SMS channel.
  Future<void> retryFailed({required String jobId}) async {
    final failed = state
        .where((r) => r.jobId == jobId && r.status == DeliveryStatus.failed)
        .toList();
    if (failed.isEmpty) return;

    final subscriptionId =
        ref.read(settingsRepositoryProvider).selectedSimSubscriptionId;
    final repo = ref.read(reportsRepositoryProvider);

    for (final record in failed) {
      final ok = await SmsChannel.sendSms(
        number: record.number,
        message: record.messageBody,
        subscriptionId: subscriptionId >= 0 ? subscriptionId : null,
      );
      record.status = ok ? DeliveryStatus.sent : DeliveryStatus.failed;
      record.errorMessage = ok ? null : 'Retry failed';
      await repo.save(record);
    }
    refresh();
  }
}

final reportsProvider =
    NotifierProvider<ReportsNotifier, List<DeliveryRecord>>(
  ReportsNotifier.new,
);
