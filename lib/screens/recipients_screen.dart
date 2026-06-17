import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../models/contact_group.dart';
import '../providers/groups_provider.dart';
import '../providers/recipients_provider.dart';

class RecipientsScreen extends ConsumerStatefulWidget {
  const RecipientsScreen({super.key});

  @override
  ConsumerState<RecipientsScreen> createState() => _RecipientsScreenState();
}

class _RecipientsScreenState extends ConsumerState<RecipientsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _pasteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recipientsProvider);
    final canContinue = state.valid.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipients'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Paste Numbers'), Tab(text: 'Groups')],
        ),
        actions: [
          TextButton(
            onPressed: canContinue ? () => context.push('/compose') : null,
            child: Text(canContinue ? 'Compose' : 'Add recipients'),
          ),
        ],
      ),
      body: Column(
        children: [
          _RecipientStatusBar(
            state: state,
            onContinue: canContinue ? () => context.push('/compose') : null,
            onClear: canContinue
                ? () => ref.read(recipientsProvider.notifier).clear()
                : null,
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _PasteTab(controller: _pasteController),
                const _GroupsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipientStatusBar extends StatelessWidget {
  final RecipientsState state;
  final VoidCallback? onContinue;
  final VoidCallback? onClear;

  const _RecipientStatusBar({
    required this.state,
    required this.onContinue,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _CountChip(
                    icon: Icons.people,
                    label: '${state.valid.length} ready',
                    color: cs.primary,
                  ),
                  if (state.duplicateCount > 0)
                    _CountChip(
                      icon: Icons.filter_alt,
                      label: '${state.duplicateCount} duplicate(s) skipped',
                      color: cs.tertiary,
                    ),
                  if (state.invalid.isNotEmpty)
                    _CountChip(
                      icon: Icons.error_outline,
                      label: '${state.invalid.length} invalid',
                      color: cs.error,
                    ),
                  if (state.valid.isEmpty && state.invalid.isEmpty)
                    Text(
                      'Add recipients to continue.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (onClear != null)
              IconButton(
                tooltip: 'Clear recipients',
                icon: const Icon(Icons.clear_all),
                onPressed: onClear,
              ),
            FilledButton(
              onPressed: onContinue,
              child: const Text('Compose'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CountChip({
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
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PasteTab extends ConsumerWidget {
  final TextEditingController controller;
  const _PasteTab({required this.controller});

  static const _maxInvalidPreview = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recipientsProvider);
    final invalidPreview = state.invalid.take(_maxInvalidPreview).toList();
    final invalidHidden = state.invalid.length - invalidPreview.length;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Phone numbers',
              hintText:
                  '0712345678, +254712345678, 254712345678\nOne per line, comma, or semicolon separated',
              helperText: 'Duplicate numbers are skipped automatically.',
              alignLabelWithHint: true,
            ),
            onChanged: (value) =>
                ref.read(recipientsProvider.notifier).parseBlob(value),
          ),
          const SizedBox(height: 16),
          if (state.valid.isNotEmpty) ...[
            Text(
              'Ready to send',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            _RecipientsPreview(state: state),
          ],
          if (state.invalid.isNotEmpty) ...[
            const Divider(height: 28),
            Text(
              'Invalid entries',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            ...invalidPreview.map(
              (entry) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.error_outline, size: 18),
                title: Text(entry.raw),
                subtitle: Text(entry.error ?? ''),
              ),
            ),
            if (invalidHidden > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+$invalidHidden more invalid entries'),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _RecipientsPreview extends ConsumerWidget {
  final RecipientsState state;
  const _RecipientsPreview({required this.state});

  static const _maxChipPreview = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = state.valid.take(_maxChipPreview).toList();
    final hidden = state.valid.length - preview.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...preview.map(
          (recipient) => InputChip(
            label: Text(recipient.displayName ?? recipient.e164),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () => ref
                .read(recipientsProvider.notifier)
                .removeValid(recipient),
          ),
        ),
        if (hidden > 0)
          Chip(
            avatar: const Icon(Icons.more_horiz, size: 16),
            label: Text('$hidden more'),
          ),
      ],
    );
  }
}

class _GroupsTab extends ConsumerStatefulWidget {
  const _GroupsTab();

  @override
  ConsumerState<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends ConsumerState<_GroupsTab> {
  final Set<String> _selectedGroupIds = {};

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider);
    final availableIds = groups.map((group) => group.id).toSet();
    _selectedGroupIds.removeWhere((id) => !availableIds.contains(id));

    final selectedGroups = groups
        .where((group) => _selectedGroupIds.contains(group.id))
        .toList(growable: false);
    final nonEmptyGroups =
        groups.where((group) => group.numbers.isNotEmpty).toList(growable: false);
    final selectedMembers =
        selectedGroups.fold<int>(0, (sum, group) => sum + group.numbers.length);
    final allUsableSelected = nonEmptyGroups.isNotEmpty &&
        nonEmptyGroups.every((group) => _selectedGroupIds.contains(group.id));

    return Column(
      children: [
        if (groups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                Checkbox(
                  value: allUsableSelected,
                  onChanged: nonEmptyGroups.isEmpty
                      ? null
                      : (_) => _toggleAllGroups(nonEmptyGroups, allUsableSelected),
                ),
                Text(
                  selectedGroups.isEmpty
                      ? 'No groups selected'
                      : '${selectedGroups.length} selected',
                ),
                const Spacer(),
                if (selectedGroups.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_selectedGroupIds.clear),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: groups.isEmpty
              ? const _EmptyGroups()
              : ListView.separated(
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) => _GroupTile(
                    group: groups[index],
                    selected: _selectedGroupIds.contains(groups[index].id),
                    onToggle: () => _toggleGroup(groups[index]),
                    onDelete: () => _deleteGroup(groups[index]),
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectedGroups.isNotEmpty) ...[
                  Text(
                    '${selectedGroups.length} group(s), $selectedMembers saved member(s)',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed:
                      selectedGroups.isEmpty ? null : () => _useSelected(groups),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(
                    selectedGroups.isEmpty
                        ? 'Select groups to use'
                        : 'Use selected groups',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _showCreateDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('New Group'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _toggleGroup(ContactGroup group) {
    if (group.numbers.isEmpty) {
      context.push('/groups/${group.id}');
      return;
    }

    setState(() {
      if (!_selectedGroupIds.add(group.id)) {
        _selectedGroupIds.remove(group.id);
      }
    });
  }

  void _toggleAllGroups(List<ContactGroup> groups, bool allSelected) {
    setState(() {
      if (allSelected) {
        _selectedGroupIds.removeAll(groups.map((group) => group.id));
      } else {
        _selectedGroupIds.addAll(groups.map((group) => group.id));
      }
    });
  }

  void _useSelected(List<ContactGroup> groups) {
    final selectedGroups = groups
        .where((group) => _selectedGroupIds.contains(group.id))
        .toList(growable: false);
    final summary =
        ref.read(recipientsProvider.notifier).addFromGroups(selectedGroups);
    setState(_selectedGroupIds.clear);
    _showImportSnackBar(context, summary);
  }

  Future<void> _deleteGroup(ContactGroup group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
          'Delete "${group.name}" and its ${group.numbers.length} member(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(groupsProvider.notifier).delete(group.id);
    setState(() => _selectedGroupIds.remove(group.id));
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    final router = GoRouter.of(context);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Group name'),
          onSubmitted: (_) => _createGroup(dialogContext, router, ctrl),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _createGroup(dialogContext, router, ctrl),
            child: const Text('Create & Add Members'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _createGroup(
    BuildContext dialogContext,
    GoRouter router,
    TextEditingController ctrl,
  ) async {
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    final group = ContactGroup(
      id: const Uuid().v4(),
      name: name,
      numbers: const [],
      createdAt: DateTime.now(),
    );
    await ref.read(groupsProvider.notifier).add(group);
    if (dialogContext.mounted) Navigator.pop(dialogContext);
    router.push('/groups/${group.id}');
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.group_add_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          const Text('No groups yet'),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final ContactGroup group;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _GroupTile({
    required this.group,
    required this.selected,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = group.numbers.isEmpty;

    return ListTile(
      leading: Checkbox(
        value: selected,
        onChanged: isEmpty ? null : (_) => onToggle(),
      ),
      title: Text(group.name),
      subtitle: Text(
        isEmpty ? 'No members' : '${group.numbers.length} member(s)',
      ),
      onTap: onToggle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Manage group',
            onPressed: () => context.push('/groups/${group.id}'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete group',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

void _showImportSnackBar(
  BuildContext context,
  RecipientImportSummary summary,
) {
  final details = <String>[];
  if (summary.added > 0) {
    details.add('Added ${summary.added} recipient(s)');
  } else if (summary.hasInput) {
    details.add('No new recipients added');
  } else {
    details.add('No numbers found');
  }
  if (summary.duplicates > 0) {
    details.add('${summary.duplicates} duplicate(s) skipped');
  }
  if (summary.invalid > 0) {
    details.add('${summary.invalid} invalid skipped');
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(details.join('. '))),
  );
}
