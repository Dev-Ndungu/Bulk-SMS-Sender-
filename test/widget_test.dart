// Smoke test – verifies app starts without crashing.
// Full unit tests for phone parser and SMS calculator live in
// test/phone_parser_test.dart and test/sms_calculator_test.dart.

import 'package:bulk_sms/core/phone_parser.dart';
import 'package:bulk_sms/core/sms_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneParser', () {
    test('parses 07XXXXXXXX', () {
      final r = PhoneParser.parse('0712345678');
      expect(r.isValid, isTrue);
      expect(r.e164, '+254712345678');
    });

    test('parses +254XXXXXXXXX unchanged', () {
      final r = PhoneParser.parse('+254712345678');
      expect(r.isValid, isTrue);
      expect(r.e164, '+254712345678');
    });

    test('parses 254XXXXXXXXX (no +)', () {
      final r = PhoneParser.parse('254712345678');
      expect(r.isValid, isTrue);
      expect(r.e164, '+254712345678');
    });

    test('rejects 8-digit number', () {
      final r = PhoneParser.parse('07123456');
      expect(r.isValid, isFalse);
    });
  });

  group('SmsCalculator', () {
    test('single GSM-7 segment', () {
      final info = SmsCalculator.calculate('Hello');
      expect(info.segments, 1);
      expect(info.isUnicode, isFalse);
    });

    test('multi segment when >160 chars', () {
      final long = 'A' * 161;
      final info = SmsCalculator.calculate(long);
      expect(info.segments, 2);
    });

    test('unicode detected', () {
      final info = SmsCalculator.calculate('🇰🇪');
      expect(info.isUnicode, isTrue);
    });
  });
}
