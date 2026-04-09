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

  /// GSM-7 basic character set (single code-unit each).
  static const _gsm7Basic = r'@£$¥èéùìòÇ'
      '\n'
      r'ØøÅåΔ_ΦΓΛΩΠΨΣΘΞ'
      '\x1b' // ESC (extension table prefix)
      r'ÆæßÉ !"#¤%&' "'" r'()*+,-./0123456789:;<=>?'
      r'¡ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      r'ÄÖÑÜ`¿abcdefghijklmnopqrstuvwxyz'
      r'äöñüà';

  /// GSM-7 extension characters (each costs 2 code-units).
  static const _gsm7Ext = r'{}[]\~|^€';

  static bool _isGsm7(String text) {
    for (final ch in text.runes) {
      final c = String.fromCharCode(ch);
      if (!_gsm7Basic.contains(c) && !_gsm7Ext.contains(c)) return false;
    }
    return true;
  }

  static int _gsm7Length(String text) {
    int len = 0;
    for (final ch in text.runes) {
      final c = String.fromCharCode(ch);
      len += _gsm7Ext.contains(c) ? 2 : 1;
    }
    return len;
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
