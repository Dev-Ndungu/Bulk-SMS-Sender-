library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/phone_parser.dart';
import '../models/contact_group.dart';
import '../models/recipient.dart';

class RecipientImportSummary {
  final int total;
  final int added;
  final int duplicates;
  final int invalid;

  const RecipientImportSummary({
    required this.total,
    required this.added,
    required this.duplicates,
    required this.invalid,
  });

  bool get hasInput => total > 0;
  bool get hasChanges => added > 0;
}

class RecipientsState {
  final List<Recipient> valid;
  final List<ParseResult> invalid;
  final int duplicateCount;

  /// Name of the group these recipients came from (if any).
  final String? groupName;

  const RecipientsState({
    this.valid = const [],
    this.invalid = const [],
    this.duplicateCount = 0,
    this.groupName,
  });

  RecipientsState copyWith({
    List<Recipient>? valid,
    List<ParseResult>? invalid,
    int? duplicateCount,
    String? groupName,
    bool clearGroupName = false,
  }) =>
      RecipientsState(
        valid: valid ?? this.valid,
        invalid: invalid ?? this.invalid,
        duplicateCount: duplicateCount ?? this.duplicateCount,
        groupName: clearGroupName ? null : (groupName ?? this.groupName),
      );
}

class RecipientsNotifier extends Notifier<RecipientsState> {
  @override
  RecipientsState build() => const RecipientsState();

  static String? _mergeGroupName(String? current, String? incoming) {
    final next = incoming?.trim();
    if (next == null || next.isEmpty) return current;
    if (current == null || current.trim().isEmpty) return next;

    final parts = current.split(' + ').where((p) => p.trim().isNotEmpty);
    final labels = <String>{...parts};
    if (!labels.add(next)) return current;
    return labels.join(' + ');
  }

  static String? _groupLabel(Iterable<ContactGroup> groups) {
    final names = groups
        .map((group) => group.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (names.isEmpty) return null;
    if (names.length <= 3) return names.join(' + ');
    return '${names.take(3).join(' + ')} + ${names.length - 3} more';
  }

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
    final seen = <String>{};
    final valid = <Recipient>[];
    var duplicates = 0;

    for (final result in results.where((r) => r.isValid)) {
      final e164 = result.e164!;
      if (!seen.add(e164)) {
        duplicates++;
        continue;
      }
      valid.add(Recipient(e164: e164));
    }

    final invalid = results.where((r) => !r.isValid).toList();
    state = RecipientsState(
      valid: valid,
      invalid: invalid,
      duplicateCount: duplicates,
    );
  }

  /// Add recipients from a list of numbers.
  RecipientImportSummary addFromGroup(
    List<String> e164Numbers, {
    String? groupName,
  }) {
    return _appendNumbers(e164Numbers, groupName: groupName);
  }

  /// Add recipients from several groups at once, deduplicating across all of
  /// them and against recipients already selected in the campaign.
  RecipientImportSummary addFromGroups(Iterable<ContactGroup> groups) {
    final selectedGroups = groups.toList(growable: false);
    return _appendNumbers(
      selectedGroups.expand((group) => group.numbers),
      groupName: _groupLabel(selectedGroups),
    );
  }

  RecipientImportSummary _appendNumbers(
    Iterable<String> rawNumbers, {
    String? groupName,
  }) {
    final existing = state.valid.map((r) => r.e164).toSet();
    final newValid = <Recipient>[];
    var total = 0;
    var duplicates = 0;
    var invalid = 0;

    for (final raw in rawNumbers) {
      total++;
      final e164 = PhoneParser.normalize(raw);
      if (e164 == null) {
        invalid++;
        continue;
      }
      if (!existing.add(e164)) {
        duplicates++;
        continue;
      }
      newValid.add(Recipient(e164: e164));
    }

    state = state.copyWith(
      valid: [...state.valid, ...newValid],
      duplicateCount: duplicates,
      groupName: _mergeGroupName(state.groupName, groupName),
    );

    return RecipientImportSummary(
      total: total,
      added: newValid.length,
      duplicates: duplicates,
      invalid: invalid,
    );
  }

  void removeValid(Recipient r) {
    final nextValid = state.valid.where((v) => v != r).toList();
    state = state.copyWith(
      valid: nextValid,
      clearGroupName: nextValid.isEmpty,
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
