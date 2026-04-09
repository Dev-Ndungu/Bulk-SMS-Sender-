/// Initialises Hive and opens all application boxes.
library;

import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants.dart';
import '../models/contact_group.dart';
import '../models/delivery_record.dart';

class HiveService {
  HiveService._();

  static Box<ContactGroup>? _groupsBox;
  static Box<DeliveryRecord>? _reportsBox;
  static Box<dynamic>? _settingsBox;
  static Box<dynamic>? _campaignsBox;
  static Box<dynamic>? _inboxBox;

  static Box<ContactGroup> get groups => _groupsBox!;
  static Box<DeliveryRecord> get reports => _reportsBox!;
  static Box<dynamic> get settings => _settingsBox!;
  static Box<dynamic> get campaigns => _campaignsBox!;
  static Box<dynamic> get inbox => _inboxBox!;

  /// Call once from `main()` before `runApp`.
  static Future<void> init() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ContactGroupAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(DeliveryRecordAdapter());
    }

    _groupsBox = await Hive.openBox<ContactGroup>(AppConstants.boxGroups);
    _reportsBox = await Hive.openBox<DeliveryRecord>(AppConstants.boxReports);
    _settingsBox = await Hive.openBox<dynamic>(AppConstants.boxSettings);
    _campaignsBox = await Hive.openBox<dynamic>(AppConstants.boxCampaigns);
    _inboxBox = await Hive.openBox<dynamic>(AppConstants.boxInbox);
  }

  static Future<void> close() async {
    await Hive.close();
  }
}
