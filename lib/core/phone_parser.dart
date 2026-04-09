/// Kenyan phone-number parser.
///
/// Accepted formats (all normalised to E.164 `+254XXXXXXXXX`):
///  • 07XXXXXXXX  (Safaricom / Airtel / Telkom 10-digit local)
///  • 01XXXXXXXX  (special short local)
///  • 254XXXXXXXXX (country code, no +)
///  • +254XXXXXXXXX (E.164 – already correct)
library;

class ParseResult {
  final String raw;
  final String? e164;
  final String? error;

  const ParseResult.ok(this.raw, this.e164) : error = null;
  const ParseResult.err(this.raw, this.error) : e164 = null;

  bool get isValid => e164 != null;
}

class PhoneParser {
  PhoneParser._();

  /// Strips all spaces, dashes, dots, parentheses from [raw].
  static String _clean(String raw) =>
      raw.replaceAll(RegExp(r'[\s\-.()\u00A0]'), '');

  /// Returns `true` if the 9-digit subscriber number portion is plausibly
  /// Kenyan (starts with 7x, 1x).
  static bool _isKenyanSubscriber(String nineDigits) {
    final prefix = nineDigits.substring(0, 2);
    // Common Kenyan prefixes: 70-79, 10-15, 20 (Safaricom), 11x
    return RegExp(r'^(7[0-9]|1[0-5]|20|11)').hasMatch(prefix);
  }

  static ParseResult parse(String raw) {
    final cleaned = _clean(raw.trim());

    if (cleaned.isEmpty) {
      return ParseResult.err(raw, 'Empty number');
    }

    String subscriber; // will be 9 digits

    if (cleaned.startsWith('+254') && cleaned.length == 13) {
      subscriber = cleaned.substring(4);
    } else if (cleaned.startsWith('254') && cleaned.length == 12) {
      subscriber = cleaned.substring(3);
    } else if (cleaned.startsWith('0') && cleaned.length == 10) {
      // 07XXXXXXXX or 01XXXXXXXX
      subscriber = cleaned.substring(1);
    } else {
      return ParseResult.err(raw, 'Unrecognised format (${cleaned.length} digits)');
    }

    if (subscriber.length != 9) {
      return ParseResult.err(raw, 'Wrong length (${cleaned.length} digits)');
    }

    if (!_isKenyanSubscriber(subscriber)) {
      return ParseResult.err(raw, 'Non-Kenyan subscriber prefix');
    }

    final e164 = '+254$subscriber';
    return ParseResult.ok(raw, e164);
  }

  /// Returns a canonical E.164 number if [raw] is valid, otherwise `null`.
  static String? normalize(String raw) => parse(raw).e164;

  /// Parse a blob of text (newline / comma / semicolon separated numbers).
  static List<ParseResult> parseBlob(String blob) {
    final tokens = blob.split(RegExp(r'[\n,;]+'));
    return tokens
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .map(parse)
        .toList();
  }
}
