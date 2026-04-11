/// Dart wrapper around the native Android SMS MethodChannel + EventChannel.
library;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sms_message.dart';

// ── SimCard ──────────────────────────────────────────────────────────────────

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

  factory SimCard.fromMap(Map<Object?, Object?> m) => SimCard(
        subscriptionId: (m['subscriptionId'] as num?)?.toInt() ?? -1,
        displayName: (m['displayName'] as String?) ?? 'SIM',
        carrierName: (m['carrierName'] as String?) ?? '',
        slotIndex: (m['slotIndex'] as num?)?.toInt() ?? 0,
        number: (m['number'] as String?) ?? '',
      );

  String get label => carrierName.isNotEmpty
      ? '$displayName ($carrierName)'
      : displayName;

  @override
  String toString() => label;
}

// ── Channel ──────────────────────────────────────────────────────────────────

class SmsChannel {
  SmsChannel._();

  static const _ch = MethodChannel('com.example.bulk_sms/sms');

  /// Returns the list of active SIM cards on the device.
  static Future<List<SimCard>> getSimCards() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getSimCards') ?? [];
      return raw
          .map((e) => SimCard.fromMap(e as Map<Object?, Object?>))
          .toList();
    } on PlatformException catch (_) {
      return const [
        SimCard(
          subscriptionId: -1,
          displayName: 'Default SIM',
          carrierName: '',
          slotIndex: 0,
          number: '',
        )
      ];
    }
  }

  /// Sends [message] to [number] using the SIM identified by [subscriptionId].
  /// Returns `true` if the native call completed without throwing.
  static Future<bool> sendSms({
    required String number,
    required String message,
    int? subscriptionId,
  }) async {
    final smsPermission = await Permission.sms.request();
    if (!smsPermission.isGranted) {
      return false;
    }

    try {
      await _ch.invokeMethod<bool>('sendSms', {
        'number': number,
        'message': message,
        if (subscriptionId != null && subscriptionId >= 0)
          'subscriptionId': subscriptionId,
      });
      return true;
    } catch (_) {
      // PlatformException, MissingPluginException, or any other error.
      return false;
    }
  }

  /// Starts a background bulk-send job on Android.
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
    if (!smsPermission.isGranted) {
      return false;
    }

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

  /// Returns all known bulk-send jobs from the native store.
  static Future<List<Map<String, dynamic>>> getBulkSendJobs() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getBulkSendJobs') ?? [];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Cancels a native background bulk-send job.
  static Future<bool> cancelBulkSend(String jobId) async {
    try {
      return await _ch.invokeMethod<bool>('cancelBulkSend', {'jobId': jobId}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` if this app is the device's default SMS app.
  static Future<bool> isDefaultSmsApp() async {
    try {
      return await _ch.invokeMethod<bool>('isDefaultSmsApp') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Prompts the user to set this app as the default SMS app.
  /// Returns `true` if the user accepted.
  static Future<bool> requestDefaultSmsApp() async {
    try {
      return await _ch.invokeMethod<bool>('requestDefaultSmsApp') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  // ── System SMS inbox ───────────────────────────────────────────────────

  /// Returns conversation threads from the system SMS database.
  /// Each entry has: number, body (last msg), timestamp, type (1=inbox, 2=sent).
  static Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>('getConversations') ?? [];
      return raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Returns all messages for a specific number from the system SMS database.
  static Future<List<SmsMessage>> getMessagesForNumber(String number) async {
    try {
      final raw = await _ch.invokeMethod<List<dynamic>>(
          'getMessagesForNumber', {'number': number}) ?? [];
      return raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return SmsMessage(
          number: m['number'] as String,
          body: m['body'] as String,
          timestamp:
              DateTime.fromMillisecondsSinceEpoch((m['timestamp'] as int)),
          direction:
              (m['type'] as int) == 1 ? SmsDirection.received : SmsDirection.sent,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Incoming SMS stream ───────────────────────────────────────────────────

  static const _eventCh = EventChannel('com.example.bulk_sms/incoming_sms');
  static Stream<SmsMessage>? _incomingStream;

  /// Broadcast stream of incoming SMS messages (singleton).
  static Stream<SmsMessage> get incomingSms {
    _incomingStream ??= _eventCh
        .receiveBroadcastStream()
        .map<SmsMessage>((event) {
          final m = Map<String, dynamic>.from(event as Map);
          return SmsMessage(
            number: m['sender'] as String,
            body: m['body'] as String,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                (m['timestamp'] as int)),
            direction: SmsDirection.received,
          );
        })
        .asBroadcastStream();
    return _incomingStream!;
  }
}
