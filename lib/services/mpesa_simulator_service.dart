library;

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/phone_parser.dart';
import 'sms_channel.dart';

class MpesaSimulatorService {
  MpesaSimulatorService._();

  static const String defaultMerchantName = 'M-PESA';
  static const String defaultSenderName = 'OMAR MOHAMED OLOW';
  static const String defaultCost = '4.95';
  static const double defaultStartingBalance = 1575.05;

  static Future<bool> sendTillSimulation({
    required String number,
    required int messageCount,
    required double amount,
    required Duration interval,
    double startingBalance = defaultStartingBalance,
    String merchantName = defaultMerchantName,
    String senderName = defaultSenderName,
  }) async {
    final normalized = PhoneParser.normalize(number) ?? number.trim();
    if (normalized.isEmpty || messageCount <= 0) return false;

    final runId = const Uuid().v4().replaceAll('-', '').toUpperCase();
    final now = DateTime.now();
    final baseDate = DateFormat('d/M/yy').format(now);
    final baseTime = DateFormat('h:mm a').format(now);
    final amountText = amount.toStringAsFixed(2);

    final recipients = List.generate(messageCount, (index) {
      final txRef = '${runId.substring(0, 10)}${index + 1}';
      final balance = (startingBalance + amount * (index + 1)).toStringAsFixed(2);
      return <String, dynamic>{
        'number': normalized,
        'displayName': merchantName,
        'mergeTags': <String, String>{
          'ref': txRef,
          'amount': amountText,
          'balance': balance,
          'cost': defaultCost,
          'date': baseDate,
          'time': baseTime,
          'sender': senderName,
        },
      };
    });

    final message =
        '{{ref}} Confirmed.on {{date}} at {{time}} KSH{{amount}} received from '
        '{{sender}}. New Account balance is KSH{{balance}}. '
        'Transaction cost, KSH{{cost}}.';

    return SmsChannel.startBulkSend(
      jobId: 'mpesa-sim-$runId',
      recipients: recipients,
      message: message,
      groupName: 'M-Pesa Simulator',
      delayMs: interval.inMilliseconds,
      batchSize: messageCount,
    );
  }
}