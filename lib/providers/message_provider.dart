library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sms_calculator.dart';

class MessageState {
  final String body;
  final DateTime? scheduledAt;
  final SmsInfo info;

  const MessageState({
    this.body = '',
    this.scheduledAt,
    required this.info,
  });

  MessageState copyWith({
    String? body,
    DateTime? scheduledAt,
    bool clearSchedule = false,
    SmsInfo? info,
  }) =>
      MessageState(
        body: body ?? this.body,
        scheduledAt:
            clearSchedule ? null : (scheduledAt ?? this.scheduledAt),
        info: info ?? this.info,
      );
}

class MessageNotifier extends Notifier<MessageState> {
  @override
  MessageState build() => MessageState(info: SmsCalculator.calculate(''));

  void setBody(String body) {
    state = state.copyWith(body: body, info: SmsCalculator.calculate(body));
  }

  void setSchedule(DateTime? dt) {
    if (dt == null) {
      state = state.copyWith(clearSchedule: true);
    } else {
      state = state.copyWith(scheduledAt: dt);
    }
  }

  void clear() {
    state = MessageState(info: SmsCalculator.calculate(''));
  }
}

final messageProvider = NotifierProvider<MessageNotifier, MessageState>(
  MessageNotifier.new,
);
