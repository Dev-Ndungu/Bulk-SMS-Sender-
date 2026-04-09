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

    test('detects unicode content', () {
      final info = SmsCalculator.calculate('🇰🇪');
      expect(info.isUnicode, isTrue);
      expect(info.segments, 1);
    });
  });
}