/// Dart wrapper around the native Android SMS MethodChannel + EventChannel.
library;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sms_message.dart';

class SimCard {
  final int subscriptionId;
  final String displayName;
  final String carrierName;
  final int slotIndex;
  final String number;

  const SimCard({
    required this.subscriptionId,
    required this.displayName,
    required this.carrierName,
    required this.slotIndex,
    required this.number,
  });

  factory SimCard.fromMap(Map<Object?, Object?> map) => SimCard(
        subscriptionId: (map['subscriptionId'] as num?)?.toInt() ?? -1,
        displayName: (map['displayName'] as String?) ?? 'SIM',
        carrierName: (map['carrierName'] as String?) ?? '',
        slotIndex: (map['slotIndex'] as num?)?.toInt() ?? 0,
        number: (map['number'] as String?) ?? '',
      );

  String get label =>
      carrierName.isNotEmpty ? '$displayName ($carrierName)' : displayName;

  @override
  String toString() => label;
}

class SmsChannel {
  SmsChannel._();

  static const _ch = MethodChannel('com.example.bulk_sms/sms');
  static const _eventCh = EventChannel('com.example.bulk_sms/incoming_sms');
  static Stream<SmsMessage>? _incomingStream;

  static Future<List<SimCard>> getSimCards() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getSimCards') ?? [];
      return raw
          .map((item) => SimCard.fromMap(item as Map<Object?, Object?>))
          .toList(growable: false);
    } catch (_) {
      return const [
        SimCard(
          subscriptionId: -1,
          displayName: 'Default SIM',
          carrierName: '',
          slotIndex: 0,
          number: '',
        ),
      ];
    }
  }

  static Future<bool> sendSms({
    required String number,
    required String message,
    int? subscriptionId,
  }) async {
    final smsPermission = await Permission.sms.request();
    if (!smsPermission.isGranted) return false;

    try {
      await _ch.invokeMethod<bool>('sendSms', {
        'number': number,
        'message': message,
        if (subscriptionId != null && subscriptionId >= 0)
          'subscriptionId': subscriptionId,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> startBulkSend({
    required String jobId,
    required List<Map<String, dynamic>> recipients,
    required String message,
    int? subscriptionId,
    String? groupName,
    int delayMs = 0,
    int batchSize = 50,
  }) async {
    final smsPermission = await Permission.sms.request();
    if (!smsPermission.isGranted) return false;

    try {
      await _ch.invokeMethod<bool>('startBulkSend', {
        'jobId': jobId,
        'recipients': recipients,
        'message': message,
        if (subscriptionId != null && subscriptionId >= 0)
          'subscriptionId': subscriptionId,
        if (groupName != null) 'groupName': groupName,
        'delayMs': delayMs,
        'batchSize': batchSize,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getBulkSendJobs() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getBulkSendJobs') ?? [];
      return raw
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getBulkSendJob(
    String jobId, {
    int recordsFrom = 0,
  }) async {
    try {
      final raw = await _ch.invokeMethod<Map<dynamic, dynamic>>(
        'getBulkSendJob',
        {'jobId': jobId, 'recordsFrom': recordsFrom},
      );
      return raw == null ? null : Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> cancelBulkSend(String jobId) async {
    try {
      return await _ch.invokeMethod<bool>(
            'cancelBulkSend',
            {'jobId': jobId},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> clearBulkSendJob(String jobId) async {
    try {
      return await _ch.invokeMethod<bool>(
            'clearBulkSendJob',
            {'jobId': jobId},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isDefaultSmsApp() async {
    try {
      return await _ch.invokeMethod<bool>('isDefaultSmsApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestDefaultSmsApp() async {
    try {
      return await _ch.invokeMethod<bool>('requestDefaultSmsApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getConversations') ?? [];
      return raw
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  static Future<List<SmsMessage>> getMessagesForNumber(String number) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
            'getMessagesForNumber',
            {'number': number},
          ) ??
          [];
      return raw.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return SmsMessage(
          id: (map['id'] as num?)?.toInt(),
          number: map['number'] as String,
          body: map['body'] as String,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (map['timestamp'] as num).toInt(),
          ),
          direction:
              (map['type'] as int) == 1 ? SmsDirection.received : SmsDirection.sent,
        );
      }).toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  static Future<bool> deleteSmsMessage(int messageId) async {
    try {
      return await _ch.invokeMethod<bool>(
            'deleteSmsMessage',
            {'messageId': messageId},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<int> deleteConversation(String number) async {
    try {
      return await _ch.invokeMethod<int>(
            'deleteConversation',
            {'number': number},
          ) ??
          0;
    } catch (_) {
      return 0;
    }
  }

  static Stream<SmsMessage> get incomingSms {
    _incomingStream ??= _eventCh.receiveBroadcastStream().map<SmsMessage>(
      (event) {
        final map = Map<String, dynamic>.from(event as Map);
        return SmsMessage(
          number: map['sender'] as String,
          body: map['body'] as String,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (map['timestamp'] as num).toInt(),
          ),
          direction: SmsDirection.received,
        );
      },
    ).asBroadcastStream();
    return _incomingStream!;
  }
}
