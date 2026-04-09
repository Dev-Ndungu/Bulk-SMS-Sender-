/// Represents a single bulk send job (not persisted, lives in provider).
library;

import 'recipient.dart';

enum JobStatus { idle, running, cancelled, done }

class SendJob {
  final String id;
  final List<Recipient> recipients;
  final String message;
  final DateTime? scheduledAt;
  final JobStatus status;
  final int sent;
  final int failed;

  const SendJob({
    required this.id,
    required this.recipients,
    required this.message,
    this.scheduledAt,
    this.status = JobStatus.idle,
    this.sent = 0,
    this.failed = 0,
  });

  int get total => recipients.length;
  int get processed => sent + failed;
  double get progress => total == 0 ? 0 : processed / total;

  SendJob copyWith({
    JobStatus? status,
    int? sent,
    int? failed,
  }) =>
      SendJob(
        id: id,
        recipients: recipients,
        message: message,
        scheduledAt: scheduledAt,
        status: status ?? this.status,
        sent: sent ?? this.sent,
        failed: failed ?? this.failed,
      );
}
