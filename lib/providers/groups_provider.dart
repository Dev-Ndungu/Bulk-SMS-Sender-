library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/contact_group.dart';
import '../repositories/groups_repository.dart';

final groupsRepositoryProvider = Provider<GroupsRepository>(
  (_) => GroupsRepository(),
);

class GroupsNotifier extends Notifier<List<ContactGroup>> {
  @override
  List<ContactGroup> build() {
    final repo = ref.read(groupsRepositoryProvider);
    final groups = repo.getAll();
    unawaited(repo.cleanupDuplicates());
    return groups;
  }

  Future<void> add(ContactGroup group) async {
    final repo = ref.read(groupsRepositoryProvider);
    await repo.save(group);
    state = repo.getAll();
  }

  Future<void> update(ContactGroup group) async {
    final repo = ref.read(groupsRepositoryProvider);
    await repo.save(group);
    state = repo.getAll();
  }

  Future<void> delete(String id) async {
    final repo = ref.read(groupsRepositoryProvider);
    await repo.delete(id);
    state = repo.getAll();
  }
}

final groupsProvider = NotifierProvider<GroupsNotifier, List<ContactGroup>>(
  GroupsNotifier.new,
);
