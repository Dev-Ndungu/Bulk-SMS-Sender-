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
  final _searchCtrl = TextEditingController();
  final _pasteCtrl = TextEditingController();
  final Set<String> _selectedContactIds = {};
  String _query = '';
  List<ParseResult> _parseResults = [];
  bool _addingContacts = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
    _pasteCtrl.addListener(() {
      setState(() => _parseResults = PhoneParser.parseBlob(_pasteCtrl.text));
    });
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

  ContactGroup? _group(List<ContactGroup> groups) {
    for (final group in groups) {
      if (group.id == widget.groupId) return group;
    }
    return null;
  }

  List<Contact> _filtered(List<Contact> all) {
    if (_query.isEmpty) return all;
    final q = _query;
    return all.where((contact) {
      if (contact.displayName.toLowerCase().contains(q)) return true;
      return contact.phones.any((phone) => phone.number.contains(q));
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider);
    final contactsState =
        ref.watch(contactsProvider).valueOrNull ?? const ContactsState();
    final group = _group(groups);

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const Center(
          child: Text('Group not found. It may have been deleted.'),
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
            const Tab(icon: Icon(Icons.contacts), text: 'Contacts'),
            const Tab(icon: Icon(Icons.paste), text: 'Paste'),
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
            phonesReady: contactsState.phonesReady,
            phoneLoadError: contactsState.phoneLoadError,
            adding: _addingContacts,
            loading: contactsState.loading && contactsState.contacts.isEmpty,
            permissionError: contactsState.permissionError,
            selected: _selectedContactIds,
            query: _query,
            searchCtrl: _searchCtrl,
            onToggle: (id) => setState(() {
              if (!_selectedContactIds.add(id)) {
                _selectedContactIds.remove(id);
              }
            }),
            onToggleAll: (contacts, allSelected) => setState(() {
              final ids = contacts.map((contact) => contact.id);
              if (allSelected) {
                _selectedContactIds.removeAll(ids);
              } else {
                _selectedContactIds.addAll(ids);
              }
            }),
            onAddSelected: () =>
                _addSelectedContacts(group, contactsState.contacts),
            onReload: () => ref.read(contactsProvider.notifier).reload(),
          ),
          _PasteTab(
            ctrl: _pasteCtrl,
            results: _parseResults,
            existingNumbers: group.numbers.toSet(),
            onAdd: () => _addPastedNumbers(group),
          ),
        ],
      ),
    );
  }

  Future<void> _removeMember(ContactGroup group, String number) async {
    final updated = group.copyWith(
      numbers: group.numbers.where((item) => item != number).toList(),
    );
    await ref.read(groupsProvider.notifier).update(updated);
  }

  Future<void> _addSelectedContacts(
    ContactGroup group,
    List<Contact> allContacts,
  ) async {
    if (_addingContacts) return;
    setState(() => _addingContacts = true);
    final selectedIds = _selectedContactIds.toSet();
    try {
      final resolvedContacts = await ref
          .read(contactsProvider.notifier)
          .getContactsWithPhones(selectedIds);
      final byId = {
        for (final contact in allContacts) contact.id: contact,
        for (final contact in resolvedContacts) contact.id: contact,
      };
      final existing = group.numbers.toSet();
      final newNumbers = <String>[];
      var duplicates = 0;
      var invalid = 0;

      for (final id in selectedIds) {
        final contact = byId[id];
        final normalized =
            contact == null ? null : _normalizedContactPhone(contact);
        if (normalized == null) {
          invalid++;
          continue;
        }
        if (!existing.add(normalized)) {
          duplicates++;
          continue;
        }
        newNumbers.add(normalized);
      }

      if (newNumbers.isNotEmpty) {
        final updated =
            group.copyWith(numbers: [...group.numbers, ...newNumbers]);
        await ref.read(groupsProvider.notifier).update(updated);
      }

      if (!mounted) return;
      setState(_selectedContactIds.clear);
      _showGroupSnackBar(
        context,
        added: newNumbers.length,
        duplicates: duplicates,
        invalid: invalid,
      );
    } finally {
      if (mounted) {
        setState(() => _addingContacts = false);
      }
    }
  }

  Future<void> _addPastedNumbers(ContactGroup group) async {
    final existing = group.numbers.toSet();
    final newNumbers = <String>[];
    var duplicates = 0;
    var invalid = 0;

    for (final result in _parseResults) {
      if (!result.isValid) {
        invalid++;
        continue;
      }
      final e164 = result.e164!;
      if (!existing.add(e164)) {
        duplicates++;
        continue;
      }
      newNumbers.add(e164);
    }

    if (newNumbers.isNotEmpty) {
      final updated = group.copyWith(numbers: [...group.numbers, ...newNumbers]);
      await ref.read(groupsProvider.notifier).update(updated);
      _pasteCtrl.clear();
    }

    if (mounted) {
      _showGroupSnackBar(
        context,
        added: newNumbers.length,
        duplicates: duplicates,
        invalid: invalid,
      );
    }
  }
}

class _MembersTab extends StatelessWidget {
  final ContactGroup group;
  final Future<void> Function(ContactGroup, String) onRemove;
  const _MembersTab({required this.group, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (group.numbers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_off,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text('No members yet'),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: group.numbers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final number = group.numbers[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.phone)),
          title: Text(number),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.remove_circle_outline),
            color: Theme.of(context).colorScheme.error,
            onPressed: () => onRemove(group, number),
          ),
        );
      },
    );
  }
}

class _ContactsTab extends StatelessWidget {
  final ContactGroup group;
  final List<Contact> contacts;
  final bool loading;
  final bool phonesLoading;
  final bool phonesReady;
  final bool adding;
  final String? permissionError;
  final String? phoneLoadError;
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
    required this.phonesReady,
    required this.adding,
    this.phoneLoadError,
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
    if (permissionError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contacts,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(permissionError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final existing = group.numbers.toSet();
    final addable = phonesReady
        ? contacts
            .where((contact) {
              final normalized = _normalizedContactPhone(contact);
              return normalized != null && !existing.contains(normalized);
            })
            .toList(growable: false)
        : contacts;
    final addableIds = addable.map((contact) => contact.id).toSet();
    final selectedAddableCount =
        selected.where((id) => addableIds.contains(id)).length;
    final allSelected =
        addableIds.isNotEmpty && addableIds.every(selected.contains);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search name or number...',
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
        if (phonesLoading || adding) const LinearProgressIndicator(minHeight: 2),
        if (phoneLoadError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(phoneLoadError!)),
                    TextButton(
                      onPressed: onReload,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
                if (selectedAddableCount > 0)
                  TextButton(
                    onPressed: adding ? null : () => onToggleAll(addable, true),
                    child: const Text('Clear'),
                  ),
                FilledButton.icon(
                  onPressed: selectedAddableCount == 0 || adding
                      ? null
                      : onAddSelected,
                  icon: adding
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add, size: 16),
                  label: Text(
                    adding ? 'Adding...' : 'Add $selectedAddableCount',
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: contacts.isEmpty
              ? Center(
                  child: Text(
                    query.isEmpty
                        ? 'No contacts found'
                        : 'No contacts match "$query"',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: contacts.length,
                  itemBuilder: (_, index) {
                    final contact = contacts[index];
                    final normalized =
                        phonesReady ? _normalizedContactPhone(contact) : null;
                    final phoneLabel =
                        phonesReady ? _contactPhoneLabel(contact) : null;
                    final alreadyIn =
                        normalized != null && existing.contains(normalized);
                    final canSelect =
                        phonesReady ? normalized != null && !alreadyIn : true;

                    return CheckboxListTile(
                      value: selected.contains(contact.id) || alreadyIn,
                      title: Text(contact.displayName),
                      subtitle: phoneLabel != null
                          ? Text(phoneLabel)
                          : phonesReady
                              ? const Text('No valid Kenyan number')
                              : const Text('Phone checked when adding'),
                      secondary: alreadyIn
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            )
                          : null,
                      onChanged: canSelect ? (_) => onToggle(contact.id) : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PasteTab extends StatelessWidget {
  final TextEditingController ctrl;
  final List<ParseResult> results;
  final Set<String> existingNumbers;
  final VoidCallback onAdd;

  const _PasteTab({
    required this.ctrl,
    required this.results,
    required this.existingNumbers,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final preview = _PastePreview.from(results, existingNumbers);

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: ctrl,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Paste numbers',
              hintText:
                  '0712345678, +254712345678, 254712345678\nOne per line, comma, or semicolon separated',
              helperText: 'Existing group members are skipped automatically.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          if (results.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _PreviewChip(
                  icon: Icons.check_circle_outline,
                  label: '${preview.newValid} new',
                  color: Theme.of(context).colorScheme.primary,
                ),
                if (preview.duplicates > 0)
                  _PreviewChip(
                    icon: Icons.filter_alt,
                    label: '${preview.duplicates} duplicate(s)',
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                if (preview.invalid > 0)
                  _PreviewChip(
                    icon: Icons.error_outline,
                    label: '${preview.invalid} invalid',
                    color: Theme.of(context).colorScheme.error,
                  ),
              ],
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: preview.newValid > 0 ? onAdd : null,
            icon: const Icon(Icons.group_add),
            label: Text('Add ${preview.newValid} to group'),
          ),
          if (preview.invalidEntries.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              'Invalid entries',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            ...preview.invalidEntries.take(20).map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline, size: 18),
                    title: Text(entry.raw),
                    subtitle: Text(entry.error ?? ''),
                  ),
                ),
            if (preview.invalidEntries.length > 20)
              Text('+${preview.invalidEntries.length - 20} more invalid'),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _PreviewChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
    );
  }
}

class _PastePreview {
  final int newValid;
  final int duplicates;
  final int invalid;
  final List<ParseResult> invalidEntries;

  const _PastePreview({
    required this.newValid,
    required this.duplicates,
    required this.invalid,
    required this.invalidEntries,
  });

  factory _PastePreview.from(
    List<ParseResult> results,
    Set<String> existingNumbers,
  ) {
    final seen = {...existingNumbers};
    final invalidEntries = <ParseResult>[];
    var newValid = 0;
    var duplicates = 0;

    for (final result in results) {
      if (!result.isValid) {
        invalidEntries.add(result);
        continue;
      }
      if (!seen.add(result.e164!)) {
        duplicates++;
        continue;
      }
      newValid++;
    }

    return _PastePreview(
      newValid: newValid,
      duplicates: duplicates,
      invalid: invalidEntries.length,
      invalidEntries: invalidEntries,
    );
  }
}

String? _normalizedContactPhone(Contact contact) {
  for (final phone in contact.phones) {
    final normalized = PhoneParser.normalize(phone.number);
    if (normalized != null) return normalized;
  }
  return null;
}

String? _contactPhoneLabel(Contact contact) {
  for (final phone in contact.phones) {
    final normalized = PhoneParser.normalize(phone.number);
    if (normalized != null) return normalized;
  }
  return contact.phones.isNotEmpty ? contact.phones.first.number : null;
}

void _showGroupSnackBar(
  BuildContext context, {
  required int added,
  required int duplicates,
  required int invalid,
}) {
  final details = <String>[];
  if (added > 0) {
    details.add('Added $added member(s)');
  } else {
    details.add('No new members added');
  }
  if (duplicates > 0) {
    details.add('$duplicates duplicate(s) skipped');
  }
  if (invalid > 0) {
    details.add('$invalid invalid skipped');
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(details.join('. '))),
  );
}
