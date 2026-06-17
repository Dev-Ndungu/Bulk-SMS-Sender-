/// GSM-7 / Unicode SMS segment calculator.
library;

import 'constants.dart';

class SmsInfo {
  final int charCount;
  final int segments;
  final bool isUnicode;
  final int charsPerSegment;
  final int remaining;

  const SmsInfo({
    required this.charCount,
    required this.segments,
    required this.isUnicode,
    required this.charsPerSegment,
    required this.remaining,
  });
}

class SmsCalculator {
  SmsCalculator._();

  /// GSM-7 basic character set. Each character costs one septet.
  static const _gsm7Basic = '@\u00A3\$\u00A5\u00E8\u00E9\u00F9'
      '\u00EC\u00F2\u00C7\n\u00D8\u00F8\r\u00C5\u00E5'
      '\u0394_\u03A6\u0393\u039B\u03A9\u03A0\u03A8\u03A3'
      '\u0398\u039E\x1B\u00C6\u00E6\u00DF\u00C9 !"#\u00A4'
      '%&\'()*+,-./0123456789:;<=>?\u00A1ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      '\u00C4\u00D6\u00D1\u00DC\u00A7\u00BFabcdefghijklmnopqrstuvwxyz'
      '\u00E4\u00F6\u00F1\u00FC\u00E0';

  /// GSM-7 extension characters. Each character costs two septets.
  static const _gsm7Ext = '{}[]\\~|^\u20AC';

  static const Map<String, String> _unicodeReplacements = {
    '\u00A0': ' ',
    '\u200B': '',
    '\uFEFF': '',
    '\u2018': "'",
    '\u2019': "'",
    '\u201A': "'",
    '\u201C': '"',
    '\u201D': '"',
    '\u201E': '"',
    '\u2013': '-',
    '\u2014': '-',
    '\u2022': '-',
    '\u2026': '...',
    '\u00A9': '(C)',
    '\u00AE': '(R)',
    '\u2122': 'TM',
  };

  static bool _isGsm7(String text) {
    for (final codePoint in text.runes) {
      final char = String.fromCharCode(codePoint);
      if (!_isGsm7Char(char)) {
        return false;
      }
    }
    return true;
  }

  static bool _isGsm7Char(String char) =>
      _gsm7Basic.contains(char) || _gsm7Ext.contains(char);

  static int _gsm7Length(String text) {
    var length = 0;
    for (final codePoint in text.runes) {
      final char = String.fromCharCode(codePoint);
      length += _gsm7Ext.contains(char) ? 2 : 1;
    }
    return length;
  }

  /// Converts common Unicode punctuation to GSM-7 equivalents and drops
  /// characters that cannot be represented in GSM-7.
  static String removeUnicode(String text) {
    final buffer = StringBuffer();

    for (final codePoint in text.runes) {
      final char = String.fromCharCode(codePoint);
      final replacement = _unicodeReplacements[char];
      if (replacement != null) {
        for (final replacementCodePoint in replacement.runes) {
          final replacementChar = String.fromCharCode(replacementCodePoint);
          if (_isGsm7Char(replacementChar)) {
            buffer.write(replacementChar);
          }
        }
        continue;
      }

      if (_isGsm7Char(char)) {
        buffer.write(char);
      }
    }

    return buffer.toString();
  }

  static SmsInfo calculate(String text) {
    if (text.isEmpty) {
      return const SmsInfo(
        charCount: 0,
        segments: 1,
        isUnicode: false,
        charsPerSegment: AppConstants.gsm7SingleLimit,
        remaining: AppConstants.gsm7SingleLimit,
      );
    }

    final unicode = !_isGsm7(text);
    final length = unicode ? text.length : _gsm7Length(text);
    final singleLimit =
        unicode ? AppConstants.unicodeSingleLimit : AppConstants.gsm7SingleLimit;
    final multiLimit =
        unicode ? AppConstants.unicodeMultiLimit : AppConstants.gsm7MultiLimit;

    if (length <= singleLimit) {
      return SmsInfo(
        charCount: length,
        segments: 1,
        isUnicode: unicode,
        charsPerSegment: singleLimit,
        remaining: singleLimit - length,
      );
    }

    final segments = (length / multiLimit).ceil();
    final remaining = segments * multiLimit - length;
    return SmsInfo(
      charCount: length,
      segments: segments,
      isUnicode: unicode,
      charsPerSegment: multiLimit,
      remaining: remaining,
    );
  }
}
