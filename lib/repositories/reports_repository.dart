/// CRUD for [DeliveryRecord] objects stored in Hive.
library;

import '../models/delivery_record.dart';
import '../services/hive_service.dart';

class ReportsRepository {
  List<DeliveryRecord> getAll() =>
      HiveService.reports.values.toList(growable: false);

  List<DeliveryRecord> getByJob(String jobId) =>
      HiveService.reports.values
          .where((r) => r.jobId == jobId)
          .toList(growable: false);

  Future<void> save(DeliveryRecord record) async {
    final key = '${record.jobId}_${record.number}';
    await HiveService.reports.put(key, record);
  }

  Future<void> saveAll(List<DeliveryRecord> records) async {
    final entries = {
      for (final r in records) '${r.jobId}_${r.number}': r,
    };
    await HiveService.reports.putAll(entries);
  }

  Future<void> deleteByJob(String jobId) async {
    final keys = HiveService.reports.keys
        .cast<String>()
        .where((k) => k.startsWith('${jobId}_'))
        .toList();
    await HiveService.reports.deleteAll(keys);
  }

  Future<void> clearAll() async {
    await HiveService.reports.clear();
  }
}
