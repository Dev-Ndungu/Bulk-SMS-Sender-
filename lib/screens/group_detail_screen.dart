import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/phone_parser.dart';
import '../models/contact_group.dart';
import '../providers/contacts_provider.dart';
import '../providers/groups_provider.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // ── Contacts tab state ────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selectedContactIds = {};

  // ── Paste tab state ───────────────────────────────────────────────────────
  final _pasteCtrl = TextEditingController();
  List<ParseResult> _parseResults = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(
        () => setState(() => _query = _searchCtrl.text.toLowerCase()));
    _pasteCtrl.addListener(() {
      setState(() => _parseResults = PhoneParser.parseBlob(_pasteCtrl.text));
    });
    // Kick off the global contacts load (no-op if already loaded/loading).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(contactsProvider.notifier).load(),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  ContactGroup? _group(List<ContactGroup> groups) =>
      groups.where((g) => g.id == widget.groupId).firstOrNull;

  List<Contact> _filtered(List<Contact> all) {
    if (_query.isEmpty) return all;
    final q = _query;
    return all.where((c) {
      if (c.displayName.toLowerCase().contains(q)) return true;
      return c.phones.any((p) => p.number.contains(q));
    }).toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider);
    final contactsState = ref.watch(contactsProvider).valueOrNull
        ?? const ContactsState();
    final group = _group(groups);

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const Center(
          child: Text('Group not found.\nIt may have been deleted.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(
              icon: const Icon(Icons.people),
              text: 'Members (${group.numbers.length})',
            ),
            const Tab(icon: Icon(Icons.contacts), text: 'Add Contacts'),
            const Tab(icon: Icon(Icons.paste), text: 'Paste Numbers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _MembersTab(group: group, onRemove: _removeMember),
          _ContactsTab(
            group: group,
            contacts: _filtered(contactsState.contacts),
            phonesLoading: contactsState.phonesLoading,
            loading: contactsState.loading && contactsState.contacts.isEmpty,
            permissionError: contactsState.permissionError,
            selected: _selectedContactIds,
            query: _query,
            searchCtrl: _searchCtrl,
            onToggle: (id) => setState(() {
              if (_selectedContactIds.contains(id)) {
                _selectedContactIds.remove(id);
              } else {
                _selectedContactIds.add(id);
              }
            }),
            onToggleAll: (contacts, allSelected) => setState(() {
              if (allSelected) {
                _selectedContactIds.removeAll(contacts.map((c) => c.id));
              } else {
                _selectedContactIds.addAll(contacts.map((c) => c.id));
              }
            }),
            onAddSelected: () => _addSelectedContacts(
                group, contactsState.contacts),
            onReload: () =>
                ref.read(contactsProvider.notifier).reload(),
          ),
          _PasteTab(
            ctrl: _pasteCtrl,
            results: _parseResults,
            onAdd: () => _addPastedNumbers(group),
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _removeMember(ContactGroup group, String number) async {
    final updated =
        group.copyWith(numbers: group.numbers.where((n) => n != number).toList());
    await ref.read(groupsProvider.notifier).update(updated);
  }

  Future<void> _addSelectedContacts(
      ContactGroup group, List<Contact> allContacts) async {
    final existing = group.numbers.toSet();
    final newNums = allContacts
        .where((c) =>
            _selectedContactIds.contains(c.id) && c.phones.isNotEmpty)
      .map((c) => PhoneParser.normalize(c.phones.first.number))
      .whereType<String>()
      .where((n) => !existing.contains(n))
        .toList();

    if (newNums.isEmpty) {
      setState(() => _selectedContactIds.clear());
      return;
    }
    final updated =
        group.copyWith(numbers: [...group.numbers, ...newNums]);
    await ref.read(groupsProvider.notifier).update(updated);
    setState(() => _selectedContactIds.clear());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${newNums.length} contact(s)')),
      );
    }
  }

  Future<void> _addPastedNumbers(ContactGroup group) async {
    final valid = _parseResults
        .where((r) => r.isValid)
        .map((r) => r.e164!)
        .where((n) => !group.numbers.contains(n))
        .toList();

    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new valid numbers to add')),
      );
      return;
    }
    final updated =
        group.copyWith(numbers: [...group.numbers, ...valid]);
    await ref.read(groupsProvider.notifier).update(updated);
    _pasteCtrl.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${valid.length} number(s)')),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tab widgets
// ═══════════════════════════════════════════════════════════════════════════════

// ── Tab 1: Members ────────────────────────────────────────────────────────────

class _MembersTab extends StatelessWidget {
  final ContactGroup group;
  final Future<void> Function(ContactGroup, String) onRemove;
  const _MembersTab({required this.group, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (group.numbers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_off, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No members yet.\nUse "Add Contacts" or "Paste Numbers" tabs.',
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: group.numbers.length,
      itemBuilder: (_, i) {
        final num = group.numbers[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.phone)),
          title: Text(num),
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: Theme.of(context).colorScheme.error,
            onPressed: () => onRemove(group, num),
          ),
        );
      },
    );
  }
}

// ── Tab 2: Add Contacts ───────────────────────────────────────────────────────

class _ContactsTab extends StatelessWidget {
  final ContactGroup group;
  final List<Contact> contacts;
  final bool loading;
  final bool phonesLoading;
  final String? permissionError;
  final Set<String> selected;
  final String query;
  final TextEditingController searchCtrl;
  final void Function(String id) onToggle;
  final void Function(List<Contact>, bool allSelected) onToggleAll;
  final VoidCallback onAddSelected;
  final VoidCallback onReload;

  const _ContactsTab({
    required this.group,
    required this.contacts,
    required this.loading,
    required this.phonesLoading,
    this.permissionError,
    required this.selected,
    required this.query,
    required this.searchCtrl,
    required this.onToggle,
    required this.onToggleAll,
    required this.onAddSelected,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    // If permission denied, show error + retry button.
    if (permissionError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.contacts, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(permissionError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('Grant Permission & Retry'),
            ),
          ],
        ),
      );
    }

    // Full spinner only while names haven't loaded yet.
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final addable = contacts
        .where((c) =>
            c.phones.isNotEmpty &&
            !group.numbers.contains(c.phones.first.number))
        .toList();
    final allSelected =
        addable.isNotEmpty && addable.every((c) => selected.contains(c.id));

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search name or number…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: searchCtrl.clear,
                    )
                  : null,
            ),
          ),
        ),

        // Phone-loading banner (names visible, phones still loading)
        if (phonesLoading)
          const LinearProgressIndicator(minHeight: 2),

        // Select-all + Add bar
        if (addable.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (_) => onToggleAll(addable, allSelected),
                ),
                const Text('Select all'),
                const Spacer(),
                if (selected.isNotEmpty)
                  FilledButton.icon(
                    onPressed: onAddSelected,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text('Add ${selected.length}'),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),

        // Contact list
        Expanded(
          child: contacts.isEmpty
              ? Center(
                  child: Text(
                    query.isEmpty
                        ? 'No contacts found.'
                        : 'No contacts match "$query".',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: contacts.length,
                  itemBuilder: (_, i) {
                    final c = contacts[i];
                    // Phase-1 contacts have no phones yet
                    final phone =
                        c.phones.isNotEmpty ? c.phones.first.number : null;
                    final alreadyIn =
                        phone != null && group.numbers.contains(phone);
                    return CheckboxListTile(
                      value: selected.contains(c.id) || alreadyIn,
                      title: Text(c.displayName),
                      subtitle: phone != null
                          ? Text(phone)
                          : phonesLoading
                              ? const Text('Loading…',
                                  style: TextStyle(
                                      color: Colors.grey,
                                      fontStyle: FontStyle.italic))
                              : null,
                      secondary: alreadyIn
                          ? Icon(Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20)
                          : null,
                      onChanged: (alreadyIn || phone == null)
                          ? null
                          : (_) => onToggle(c.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Tab 3: Paste Numbers ─────────────────────────────────────────────────────

class _PasteTab extends StatelessWidget {
  final TextEditingController ctrl;
  final List<ParseResult> results;
  final VoidCallback onAdd;

  const _PasteTab(
      {required this.ctrl, required this.results, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final valid = results.where((r) => r.isValid).length;
    final invalid = results.where((r) => !r.isValid).length;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: ctrl,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Paste numbers',
                    hintText:
                        'One per line, or comma/semicolon separated.\n'
                        'Formats: 0712345678, +254712345678, 254712345678',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                if (results.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text('$valid valid'),
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                      ),
                      if (invalid > 0)
                        Chip(
                          label: Text('$invalid invalid'),
                          backgroundColor:
                              Theme.of(context).colorScheme.errorContainer,
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: valid > 0 ? onAdd : null,
                  icon: const Icon(Icons.group_add),
                  label: Text('Add $valid number(s) to group'),
                ),
                if (invalid > 0) ...[
                  const Divider(height: 24),
                  Text('Invalid entries:',
                      style: Theme.of(context).textTheme.labelSmall),
                  ...results
                      .where((r) => !r.isValid)
                      .map((r) => ListTile(
                            dense: true,
                            leading:
                                const Icon(Icons.error_outline, size: 16),
                            title: Text(r.raw),
                            subtitle: Text(r.error ?? ''),
                          )),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


