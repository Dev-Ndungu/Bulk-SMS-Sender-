/// A single SMS message (sent or received), stored in Hive as a plain Map.
library;

enum SmsDirection { sent, received }

class SmsMessage {
  final int? id;
  final String number; // E.164 or raw sender
  final String body;
  final DateTime timestamp;
  final SmsDirection direction;

  const SmsMessage({
    this.id,
    required this.number,
    required this.body,
    required this.timestamp,
    required this.direction,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'number': number,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        'direction': direction.name,
      };

  factory SmsMessage.fromMap(Map map) => SmsMessage(
        id: (map['id'] as num?)?.toInt(),
        number: map['number'] as String,
        body: map['body'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        direction: SmsDirection.values.firstWhere(
          (d) => d.name == map['direction'],
          orElse: () => SmsDirection.received,
        ),
      );
}
