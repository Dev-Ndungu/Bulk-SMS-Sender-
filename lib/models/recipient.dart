/// A single SMS recipient.
library;

class Recipient {
  final String e164; // canonical +254XXXXXXXXX
  final String? displayName;
  final Map<String, String> mergeTags;

  const Recipient({
    required this.e164,
    this.displayName,
    this.mergeTags = const {},
  });

  @override
  bool operator ==(Object other) =>
      other is Recipient && other.e164 == e164;

  @override
  int get hashCode => e164.hashCode;

  @override
  String toString() => displayName != null ? '$displayName ($e164)' : e164;
}
