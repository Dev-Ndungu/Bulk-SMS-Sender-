/// Settings stored in Hive (all non-sensitive now – API gateway removed).
library;

import '../core/constants.dart';
import '../services/hive_service.dart';

class SettingsRepository {
  // ── SIM ─────────────────────────────────────────────────────────────────
  /// The subscriptionId of the SIM to use (-1 = device default).
  int get selectedSimSubscriptionId =>
      HiveService.settings.get('selectedSimId', defaultValue: -1) as int;

  Future<void> setSelectedSimSubscriptionId(int id) =>
      HiveService.settings.put('selectedSimId', id);

  // ── Throttling ───────────────────────────────────────────────────────────
  int get batchSize =>
      HiveService.settings.get('batchSize',
          defaultValue: AppConstants.defaultBatchSize) as int;
  Future<void> setBatchSize(int size) =>
      HiveService.settings.put('batchSize', size);

  /// Delay (ms) between individual SMS messages.
  int get interSmsDelayMs =>
      HiveService.settings.get('interSmsDelayMs',
          defaultValue: AppConstants.defaultDelayMs) as int;
  Future<void> setInterSmsDelayMs(int ms) =>
      HiveService.settings.put('interSmsDelayMs', ms);
}
