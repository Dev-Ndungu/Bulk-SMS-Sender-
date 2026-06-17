library;

import 'dart:async';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ContactsState {
  final List<Contact> basic;
  final List<Contact>? full;
  final bool loading;
  final String? permissionError;
  final String? phoneLoadError;

  const ContactsState({
    this.basic = const [],
    this.full,
    this.loading = false,
    this.permissionError,
    this.phoneLoadError,
  });

  List<Contact> get contacts => full ?? basic;
  bool get phonesReady => full != null;
  bool get phonesLoading => full == null && loading && basic.isNotEmpty;
}

class ContactsNotifier extends AsyncNotifier<ContactsState> {
  static const _basicLoadTimeout = Duration(seconds: 12);
  static const _singleContactTimeout = Duration(seconds: 5);
  final Map<String, Contact> _phoneCache = {};

  @override
  Future<ContactsState> build() async => const ContactsState();

  Future<void> load() async {
    final current = state.valueOrNull;
    if (current != null &&
        (current.loading ||
            current.full != null ||
            (current.basic.isNotEmpty && current.phoneLoadError != null))) {
      return;
    }

    state = AsyncData(
      ContactsState(
        basic: current?.basic ?? const [],
        full: current?.full,
        loading: true,
      ),
    );

    final allowed = await _requestPermission();
    if (!allowed) {
      state = const AsyncData(
        ContactsState(permissionError: 'Contacts permission denied'),
      );
      return;
    }

    final basic = await _loadBasicContacts();
    if (basic == null) {
      state = const AsyncData(
        ContactsState(
          permissionError:
              'Contacts did not respond. Retry, or use Paste to add numbers.',
        ),
      );
      return;
    }

    state = AsyncData(ContactsState(basic: basic, loading: false));
  }

  Future<void> reload() async {
    state = const AsyncData(ContactsState());
    await load();
  }

  Future<bool> _requestPermission() async {
    try {
      return await FlutterContacts.requestPermission(readonly: true)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      return false;
    }
  }

  Future<List<Contact>?> _loadBasicContacts() async {
    try {
      return await FlutterContacts.getContacts(
        withProperties: false,
        withThumbnail: false,
        withPhoto: false,
      ).timeout(_basicLoadTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<List<Contact>> getContactsWithPhones(Iterable<String> ids) async {
    final uniqueIds = ids.toSet().toList(growable: false);
    final resolved = <Contact>[];
    final missing = <String>[];

    for (final id in uniqueIds) {
      final cached = _phoneCache[id];
      if (cached != null) {
        resolved.add(cached);
      } else {
        missing.add(id);
      }
    }

    for (final id in missing) {
      final contact = await _loadSingleContactWithPhones(id);
      if (contact != null) {
        _phoneCache[contact.id] = contact;
        resolved.add(contact);
      }
    }

    return resolved;
  }

  Future<Contact?> _loadSingleContactWithPhones(String id) async {
    try {
      return await FlutterContacts.getContact(
        id,
        withProperties: true,
        withThumbnail: false,
        withPhoto: false,
        deduplicateProperties: true,
      ).timeout(_singleContactTimeout);
    } catch (_) {
      return null;
    }
  }

}

final contactsProvider =
    AsyncNotifierProvider<ContactsNotifier, ContactsState>(
  ContactsNotifier.new,
);
