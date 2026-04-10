/// CRUD for [ContactGroup] objects stored in Hive.
library;

import '../core/phone_parser.dart';
import '../models/contact_group.dart';
import '../services/hive_service.dart';

class GroupsRepository {
  List<ContactGroup> getAll() => HiveService.groups.values
      .map(_normalizeGroup)
      .toList(growable: false);

  Future<void> save(ContactGroup group) async {
    final cleaned = _normalizeGroup(group);
    await HiveService.groups.put(cleaned.id, cleaned);
  }

  Future<void> delete(String id) async {
    await HiveService.groups.delete(id);
  }

  ContactGroup? getById(String id) => HiveService.groups.get(id);

  Future<void> cleanupDuplicates() async {
    final entries = <String, ContactGroup>{};
    var changed = false;
    for (final raw in HiveService.groups.values) {
      final group = _normalizeGroup(raw);
      entries[group.id] = group;
      if (!_sameNumbers(raw.numbers, group.numbers)) {
        changed = true;
      }
    }
    if (!changed) return;
    await HiveService.groups.putAll(entries);
  }

  static ContactGroup _normalizeGroup(ContactGroup group) {
    final seen = <String>{};
    final cleaned = <String>[];

    for (final raw in group.numbers) {
      final normalized = PhoneParser.normalize(raw);
      if (normalized == null) continue;
      if (seen.add(normalized)) cleaned.add(normalized);
    }

    return group.copyWith(numbers: cleaned);
  }

  static bool _sameNumbers(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
