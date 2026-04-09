library;

import 'package:hive_flutter/hive_flutter.dart';

import '../core/constants.dart';
import '../models/campaign_summary.dart';

class CampaignsRepository {
  Box<dynamic> get _box => Hive.box<dynamic>(AppConstants.boxCampaigns);

  List<CampaignSummary> getAll() {
    return _box.values
        .whereType<Map>()
        .map(CampaignSummary.fromMap)
        .toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt)); // newest first
  }

  Future<void> save(CampaignSummary c) async {
    await _box.put(c.id, c.toMap());
  }

  Future<void> update(CampaignSummary c) => save(c);

  Future<void> delete(String id) async {
    await _box.delete(id);
  }

  Future<void> clearAll() async {
    await _box.clear();
  }
}
