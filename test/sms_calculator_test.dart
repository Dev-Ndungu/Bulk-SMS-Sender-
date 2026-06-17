import 'package:bulk_sms/core/sms_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmsCalculator', () {
    test('counts a simple GSM-7 message as one segment', () {
      final info = SmsCalculator.calculate('Hello');
      expect(info.charCount, 5);
      expect(info.segments, 1);
      expect(info.isUnicode, isFalse);
      expect(info.remaining, 155);
    });

    test('splits GSM-7 text beyond one segment', () {
      final info = SmsCalculator.calculate('A' * 161);
      expect(info.segments, 2);
      expect(info.charsPerSegment, 153);
    });

    test('counts GSM-7 extension characters as two septets', () {
      final info = SmsCalculator.calculate('Balance {KES} \u20AC');
      expect(info.isUnicode, isFalse);
      expect(info.charCount, 18);
      expect(info.segments, 1);
    });

    test('detects unicode content', () {
      final info = SmsCalculator.calculate('\u{1F1F0}\u{1F1EA}');
      expect(info.isUnicode, isTrue);
      expect(info.segments, 1);
    });
  });
}
