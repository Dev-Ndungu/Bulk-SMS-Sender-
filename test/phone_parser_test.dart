import 'package:bulk_sms/core/phone_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneParser', () {
    test('normalizes common Kenyan formats', () {
      expect(PhoneParser.normalize('0712345678'), '+254712345678');
      expect(PhoneParser.normalize('+254712345678'), '+254712345678');
      expect(PhoneParser.normalize('254712345678'), '+254712345678');
      expect(PhoneParser.normalize('0112345678'), '+254112345678');
    });

    test('rejects empty and malformed numbers', () {
      expect(PhoneParser.normalize(''), isNull);
      expect(PhoneParser.normalize('07123456'), isNull);
      expect(PhoneParser.normalize('12345'), isNull);
    });

    test('parseBlob keeps valid and invalid entries separate', () {
      final results = PhoneParser.parseBlob('0712345678, bad; +254712345678');

      expect(results.where((r) => r.isValid).length, 2);
      expect(results.where((r) => !r.isValid).length, 1);
    });
  });
}