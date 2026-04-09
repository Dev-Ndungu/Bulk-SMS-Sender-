library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/phone_parser.dart';
import '../models/recipient.dart';

class RecipientsState {
  final List<Recipient> valid;
  final List<ParseResult> invalid;
  /// Name of the group these recipients came from (if any).
  final String? groupName;

  const RecipientsState({
    this.valid = const [],
    this.invalid = const [],
    this.groupName,
  });

  RecipientsState copyWith({
    List<Recipient>? valid,
    List<ParseResult>? invalid,
    String? groupName,
  }) =>
      RecipientsState(
        valid: valid ?? this.valid,
        invalid: invalid ?? this.invalid,
        groupName: groupName ?? this.groupName,
      );
}

class RecipientsNotifier extends Notifier<RecipientsState> {
  @override
  RecipientsState build() => const RecipientsState();

  List<Recipient> _normalizeRecipients(Iterable<String> rawNumbers) {
    final seen = <String>{};
    final recipients = <Recipient>[];

    for (final raw in rawNumbers) {
      final e164 = PhoneParser.normalize(raw);
      if (e164 == null || !seen.add(e164)) continue;
      recipients.add(Recipient(e164: e164));
    }

    return recipients;
  }

  /// Parse a raw text blob and replace the current recipient list.
  void parseBlob(String blob) {
    final results = PhoneParser.parseBlob(blob);
    final valid = results
        .where((r) => r.isValid)
        .map((r) => Recipient(e164: r.e164!))
        .toSet() // deduplicate
        .toList();
    final invalid = results.where((r) => !r.isValid).toList();
    state = RecipientsState(valid: valid, invalid: invalid);
  }

  /// Add recipients from a list of numbers.
  void addFromGroup(List<String> e164Numbers, {String? groupName}) {
    final existing = state.valid.map((r) => r.e164).toSet();
    final newValid = _normalizeRecipients(e164Numbers)
        .where((r) => !existing.contains(r.e164))
        .toList();
    state = state.copyWith(
      valid: [...state.valid, ...newValid],
      groupName: groupName,
    );
  }

  void removeValid(Recipient r) {
    state = state.copyWith(
      valid: state.valid.where((v) => v != r).toList(),
    );
  }

  /// Replace the current list with the given numbers (used by history
  /// duplicate / edit-and-resend).
  void setFromNumbers(List<String> e164Numbers, {String? groupName}) {
    final valid = _normalizeRecipients(e164Numbers);
    state = RecipientsState(valid: valid, groupName: groupName);
  }

  void clear() {
    state = const RecipientsState();
  }
}

final recipientsProvider =
    NotifierProvider<RecipientsNotifier, RecipientsState>(
  RecipientsNotifier.new,
);
