/// Job-level summary stored in Hive as a plain Map (no codegen needed).
library;

class CampaignSummary {
  final String id; // jobId (UUID)
  final String message; // original template (pre-merge-tags)
  final List<String> numbers; // e164 recipient list
  final DateTime sentAt;
  final int sent;
  final int failed;
  final String? groupName;

  const CampaignSummary({
    required this.id,
    required this.message,
    required this.numbers,
    required this.sentAt,
    this.sent = 0,
    this.failed = 0,
    this.groupName,
  });

  int get total => numbers.length;

  Map<String, dynamic> toMap() => {
        'id': id,
        'message': message,
        'numbers': numbers,
        'sentAt': sentAt.toIso8601String(),
        'sent': sent,
        'failed': failed,
        'groupName': groupName,
      };

  factory CampaignSummary.fromMap(Map map) => CampaignSummary(
        id: map['id'] as String,
        message: map['message'] as String,
        numbers: List<String>.from(map['numbers'] as List),
        sentAt: DateTime.parse(map['sentAt'] as String),
        sent: (map['sent'] as int?) ?? 0,
        failed: (map['failed'] as int?) ?? 0,
        groupName: map['groupName'] as String?,
      );

  CampaignSummary copyWith({
    int? sent,
    int? failed,
    String? message,
    List<String>? numbers,
    String? groupName,
  }) =>
      CampaignSummary(
        id: id,
        message: message ?? this.message,
        numbers: numbers ?? this.numbers,
        sentAt: sentAt,
        sent: sent ?? this.sent,
        failed: failed ?? this.failed,
        groupName: groupName ?? this.groupName,
      );
}
