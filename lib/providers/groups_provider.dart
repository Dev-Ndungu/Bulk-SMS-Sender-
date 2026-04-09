library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/contact_group.dart';
import '../repositories/groups_repository.dart';

final groupsRepositoryProvider = Provider<GroupsRepository>(
  (_) => GroupsRepository(),
);

class GroupsNotifier extends Notifier<List<ContactGroup>> {
  @override
  List<ContactGroup> build() =>
      ref.read(groupsRepositoryProvider).getAll();

  Future<void> add(ContactGroup group) async {
    await ref.read(groupsRepositoryProvider).save(group);
    state = ref.read(groupsRepositoryProvider).getAll();
  }

  Future<void> update(ContactGroup group) async {
    await ref.read(groupsRepositoryProvider).save(group);
    state = ref.read(groupsRepositoryProvider).getAll();
  }

  Future<void> delete(String id) async {
    await ref.read(groupsRepositoryProvider).delete(id);
    state = ref.read(groupsRepositoryProvider).getAll();
  }
}

final groupsProvider = NotifierProvider<GroupsNotifier, List<ContactGroup>>(
  GroupsNotifier.new,
);
