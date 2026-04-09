// ignore_for_file: constant_identifier_names
/// Application-wide constants.
library;

class AppConstants {
  AppConstants._();

  // Hive box names
  static const String boxGroups = 'contact_groups';
  static const String boxReports = 'delivery_reports';
  static const String boxSettings = 'settings';
  static const String boxCampaigns = 'campaigns';
  static const String boxInbox = 'inbox';

  // Secure-storage keys
  static const String keyApiKey = 'at_api_key';
  static const String keySenderId = 'at_sender_id';
  static const String keyLastRoute = 'last_route';

  // Africa's Talking
  static const String atBaseUrl =
      'https://api.africastalking.com/version1/messaging';
  static const String atSandboxUrl =
      'https://api.sandbox.africastalking.com/version1/messaging';

  // Kenya country code
  static const String kenyaCode = '+254';

  // SMS limits
  static const int gsm7SingleLimit = 160;
  static const int gsm7MultiLimit = 153;
  static const int unicodeSingleLimit = 70;
  static const int unicodeMultiLimit = 67;

  // Default batch size between gateway calls (ms delay)
  static const int defaultBatchSize = 50;
  static const int defaultDelayMs = 500;
}
