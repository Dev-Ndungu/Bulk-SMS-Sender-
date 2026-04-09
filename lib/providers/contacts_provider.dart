library;

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Holds contacts loaded in two phases.
class ContactsState {
  /// Phase-1: display names only (fast). Empty until first load starts.
  final List<Contact> basic;

  /// Phase-2: full contacts including phone numbers. Null = still loading.
  final List<Contact>? full;

  /// True while either phase is in progress.
  final bool loading;

  /// Non-null if permission was denied.
  final String? permissionError;

  const ContactsState({
    this.basic = const [],
    this.full,
    this.loading = false,
    this.permissionError,
  });

  /// The best list to display: full when available, basic otherwise.
  List<Contact> get contacts => full ?? basic;

  /// True if phone numbers are not yet available.
  bool get phonesLoading => full == null && loading;
}

class ContactsNotifier extends AsyncNotifier<ContactsState> {
  @override
  Future<ContactsState> build() async => const ContactsState();

  /// Kick off the two-phase load. Safe to call multiple times
  /// (skips if already loaded or loading).
  Future<void> load() async {
    final cur = state.valueOrNull;
    if (cur != null && (cur.loading || cur.full != null)) return;

    // Mark loading
    state = AsyncData(const ContactsState(loading: true));

    // Permission check
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      state = const AsyncData(
        ContactsState(permissionError: 'Contacts permission denied'),
      );
      return;
    }

    // ── Phase 1: names only (very fast) ──────────────────────────────────
    final basic = await FlutterContacts.getContacts();
    state = AsyncData(ContactsState(basic: basic, loading: true));

    // ── Phase 2: with phone numbers (slower) ─────────────────────────────
    final full =
        await FlutterContacts.getContacts(withProperties: true);
    state = AsyncData(ContactsState(basic: basic, full: full, loading: false));
  }

  /// Force a fresh reload (e.g., after the user grants permission later).
  Future<void> reload() async {
    state = const AsyncData(ContactsState());
    await load();
  }
}

final contactsProvider =
    AsyncNotifierProvider<ContactsNotifier, ContactsState>(
  ContactsNotifier.new,
);
