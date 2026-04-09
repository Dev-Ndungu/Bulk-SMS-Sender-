/// Per-recipient delivery record stored in Hive.
library;

import 'package:hive_flutter/hive_flutter.dart';

part 'delivery_record.g.dart';

enum DeliveryStatus { pending, sent, delivered, failed, unknown }

@HiveType(typeId: 1)
class DeliveryRecord extends HiveObject {
  @HiveField(0)
  late String jobId;

  @HiveField(1)
  late String number; // E.164

  @HiveField(2)
  late String messageBody;

  @HiveField(3)
  late String statusStr; // serialised DeliveryStatus name

  @HiveField(4)
  late DateTime sentAt;

  @HiveField(5)
  late String? gatewayMessageId;

  @HiveField(6)
  late String? errorMessage;

  DeliveryStatus get status =>
      DeliveryStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => DeliveryStatus.unknown,
      );

  set status(DeliveryStatus v) => statusStr = v.name;

  DeliveryRecord({
    required this.jobId,
    required this.number,
    required this.messageBody,
    DeliveryStatus status = DeliveryStatus.pending,
    required this.sentAt,
    this.gatewayMessageId,
    this.errorMessage,
  }) : statusStr = status.name;
}
