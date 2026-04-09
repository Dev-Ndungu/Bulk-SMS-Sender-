/// CRUD for [ContactGroup] objects stored in Hive.
library;

import '../models/contact_group.dart';
import '../services/hive_service.dart';

class GroupsRepository {
  List<ContactGroup> getAll() =>
      HiveService.groups.values.toList(growable: false);

  Future<void> save(ContactGroup group) async {
    await HiveService.groups.put(group.id, group);
  }

  Future<void> delete(String id) async {
    await HiveService.groups.delete(id);
  }

  ContactGroup? getById(String id) => HiveService.groups.get(id);
}
