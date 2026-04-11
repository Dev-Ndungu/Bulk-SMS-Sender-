library;

import '../models/campaign_summary.dart';
import '../models/delivery_record.dart';
import '../models/recipient.dart';
import '../repositories/campaigns_repository.dart';
import '../repositories/reports_repository.dart';
import 'sms_channel.dart';

class BulkSendRecordSnapshot {
  final String number;
  final String messageBody;
  final String status;
  final DateTime sentAt;
  final String? errorMessage;

  const BulkSendRecordSnapshot({
    required this.number,
    required this.messageBody,
    required this.status,
    required this.sentAt,
    this.errorMessage,
  });

  DeliveryRecord toDeliveryRecord(String jobId) => DeliveryRecord(
        jobId: jobId,
        number: number,
        messageBody: messageBody,
        status: _parseStatus(status),
        sentAt: sentAt,
        errorMessage: errorMessage,
      );

  factory BulkSendRecordSnapshot.fromMap(Map<String, dynamic> map) =>
      BulkSendRecordSnapshot(
        number: map['number'] as String? ?? '',
        messageBody: map['messageBody'] as String? ?? '',
        status: map['status'] as String? ?? 'failed',
        sentAt: DateTime.fromMillisecondsSinceEpoch(
          (map['sentAt'] as num?)?.toInt() ?? 0,
        ),
        errorMessage: map['errorMessage'] as String?,
      );
}

class BulkSendJobSnapshot {
  final String jobId;
  final String message;
  final List<String> numbers;
  final String? groupName;
  final int delayMs;
  final int batchSize;
  final String status;
  final int sent;
  final int failed;
  final int nextIndex;
  final DateTime createdAt;
  final List<BulkSendRecordSnapshot> records;

  const BulkSendJobSnapshot({
    required this.jobId,
    required this.message,
    required this.numbers,
    required this.groupName,
    required this.delayMs,
    required this.batchSize,
    required this.status,
    required this.sent,
    required this.failed,
    required this.nextIndex,
    required this.createdAt,
    required this.records,
  });

  int get total => numbers.length;
  int get processed => sent + failed;
  bool get isComplete => status == 'completed' || status == 'cancelled';

  CampaignSummary toCampaignSummary() => CampaignSummary(
        id: jobId,
        message: message,
        numbers: numbers,
        sentAt: createdAt,
        sent: sent,
        failed: failed,
        groupName: groupName,
      );

  factory BulkSendJobSnapshot.fromMap(Map<String, dynamic> map) {
    final rawRecords = (map['records'] as List? ?? const []).cast<dynamic>();
    return BulkSendJobSnapshot(
      jobId: map['jobId'] as String? ?? '',
      message: map['message'] as String? ?? '',
      numbers: (map['numbers'] as List? ?? const []).map((e) => e.toString()).toList(),
      groupName: map['groupName'] as String?,
      delayMs: (map['delayMs'] as num?)?.toInt() ?? 0,
      batchSize: (map['batchSize'] as num?)?.toInt() ?? 50,
      status: map['status'] as String? ?? 'queued',
      sent: (map['sent'] as num?)?.toInt() ?? 0,
      failed: (map['failed'] as num?)?.toInt() ?? 0,
      nextIndex: (map['nextIndex'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
      records: rawRecords
          .whereType<Map>()
          .map((m) => BulkSendRecordSnapshot.fromMap(Map<String, dynamic>.from(m)))
          .toList(growable: false),
    );
  }
}

class BulkSendSyncService {
  BulkSendSyncService._();

  static Future<List<BulkSendJobSnapshot>> fetchNativeJobs() async {
    final jobs = await SmsChannel.getBulkSendJobs();
    return jobs.map(BulkSendJobSnapshot.fromMap).toList(growable: false);
  }

  static Future<BulkSendJobSnapshot?> fetchJob(String jobId) async {
    final jobs = await fetchNativeJobs();
    for (final job in jobs) {
      if (job.jobId == jobId) return job;
    }
    return null;
  }

  /// Sync a native snapshot into Hive.
  ///
  /// [alreadyPersistedCount] is the number of delivery records already present
  /// in Hive for this job so we only write the newly appended rows.
  static Future<void> persistSnapshot(
    BulkSendJobSnapshot snapshot, {
    int alreadyPersistedCount = 0,
  }) async {
    final campaignsRepo = CampaignsRepository();
    final reportsRepo = ReportsRepository();

    await campaignsRepo.save(snapshot.toCampaignSummary());

    final records = snapshot.records
        .skip(alreadyPersistedCount)
        .map((r) => r.toDeliveryRecord(snapshot.jobId))
        .toList(growable: false);
    if (records.isNotEmpty) {
      await reportsRepo.saveAll(records);
    }
  }

  static Future<void> syncAllPending() async {
    final jobs = await fetchNativeJobs();
    final campaignsRepo = CampaignsRepository();
    final reportsRepo = ReportsRepository();

    for (final job in jobs) {
      final existingCampaign = campaignsRepo.getById(job.jobId);
      final alreadyPersisted = (existingCampaign?.sent ?? 0) + (existingCampaign?.failed ?? 0);
      await campaignsRepo.save(job.toCampaignSummary());
      final records = job.records
          .skip(alreadyPersisted)
          .map((r) => r.toDeliveryRecord(job.jobId))
          .toList(growable: false);
      if (records.isNotEmpty) {
        await reportsRepo.saveAll(records);
      }
    }
  }
}

DeliveryStatus _parseStatus(String value) => switch (value) {
      'sent' => DeliveryStatus.sent,
      'delivered' => DeliveryStatus.delivered,
      'pending' => DeliveryStatus.pending,
      'failed' => DeliveryStatus.failed,
      _ => DeliveryStatus.unknown,
    };
