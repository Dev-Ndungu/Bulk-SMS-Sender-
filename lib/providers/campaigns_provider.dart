library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/campaign_summary.dart';
import '../repositories/campaigns_repository.dart';

final campaignsRepositoryProvider = Provider<CampaignsRepository>(
  (_) => CampaignsRepository(),
);

class CampaignsNotifier extends Notifier<List<CampaignSummary>> {
  @override
  List<CampaignSummary> build() =>
      ref.read(campaignsRepositoryProvider).getAll();

  void refresh() {
    state = ref.read(campaignsRepositoryProvider).getAll();
  }

  Future<void> save(CampaignSummary c) async {
    await ref.read(campaignsRepositoryProvider).save(c);
    refresh();
  }

  Future<void> update(CampaignSummary c) async {
    await ref.read(campaignsRepositoryProvider).update(c);
    refresh();
  }

  Future<void> delete(String id) async {
    await ref.read(campaignsRepositoryProvider).delete(id);
    refresh();
  }

  Future<void> clearAll() async {
    await ref.read(campaignsRepositoryProvider).clearAll();
    state = [];
  }
}

final campaignsProvider =
    NotifierProvider<CampaignsNotifier, List<CampaignSummary>>(
  CampaignsNotifier.new,
);
