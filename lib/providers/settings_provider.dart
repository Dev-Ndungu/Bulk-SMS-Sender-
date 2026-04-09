library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/settings_repository.dart';
import '../services/sms_channel.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (_) => SettingsRepository(),
);

// ── SIM cards ────────────────────────────────────────────────────────────────

/// Cached list of SIM cards available on the device.
final simCardsProvider = FutureProvider<List<SimCard>>((_) async {
  return SmsChannel.getSimCards();
});

/// The subscriptionId that should be used when sending SMS.
/// -1 means the device's default SIM.
final selectedSimIdProvider = Provider<int>((ref) {
  return ref.watch(settingsRepositoryProvider).selectedSimSubscriptionId;
});
