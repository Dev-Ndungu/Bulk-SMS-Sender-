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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipients'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Paste Numbers'), Tab(text: 'Groups')],
        ),
        actions: [
          if (state.valid.isNotEmpty)
            TextButton(
              onPressed: () => context.push('/compose'),
              child: Text('Next (${state.valid.length})'),
            ),
        ],
      ),
      body: TabBarView(
        controller: _tab,
        children: [_PasteTab(controller: _pasteController), const _GroupsTab()],
      ),
    );
  }
}

// ── Paste tab ────────────────────────────────────────────────────────────────

class _PasteTab extends ConsumerWidget {
  final TextEditingController controller;
  const _PasteTab({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recipientsProvider);
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
                  controller: controller,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Phone numbers',
                    hintText:
                        'Paste numbers separated by commas, new lines, '
                        'or semicolons\n'
                        'Formats: 0712345678, +254712345678, 254712345678',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (v) =>
                      ref.read(recipientsProvider.notifier).parseBlob(v),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(
                      label: Text('${state.valid.length} valid'),
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                    ),
                    if (state.invalid.isNotEmpty)
                      Chip(
                        label: Text('${state.invalid.length} invalid'),
                        backgroundColor:
                            Theme.of(context).colorScheme.errorContainer,
                      ),
                  ],
                ),
                if (state.invalid.isNotEmpty) ...[
                  const Divider(),
                  Text('Invalid numbers:',
                      style: Theme.of(context).textTheme.labelSmall),
                  ...state.invalid.map((e) => ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.error_outline, size: 16),
                        title: Text(e.raw),
                        subtitle: Text(e.error ?? ''),
                      )),
                ],
                if (state.valid.isNotEmpty) ...[
                  const Divider(),
                  Text('Valid recipients:',
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: state.valid
                        .map(
                          (r) => InputChip(
                            label:
                                Text(r.displayName ?? r.e164),
                            deleteIcon:
                                const Icon(Icons.close, size: 16),
                            onDeleted: () => ref
                                .read(recipientsProvider.notifier)
                                .removeValid(r),
                          ),
                        )
                        .toList(),
                  ),
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

// ── Groups tab ───────────────────────────────────────────────────────────────

class _GroupsTab extends ConsumerWidget {
  const _GroupsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);

    return Column(
      children: [
        if (groups.isEmpty)
          const Expanded(
            child: Center(child: Text('No groups yet. Create one below.')),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: groups.length,
              itemBuilder: (_, i) => _GroupTile(group: groups[i]),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New Group'),
          ),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    // Capture the router before entering the dialog so we can navigate even
    // after the dialog is dismissed (the dialog's own context may be stale).
    final router = GoRouter.of(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('New Group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              final group = ContactGroup(
                id: const Uuid().v4(),
                name: name,
                numbers: const [],
                createdAt: DateTime.now(),
              );
              await ref.read(groupsProvider.notifier).add(group);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              // Use the pre-captured router – safe even if the original
              // context is no longer in the tree.
              router.push('/groups/${group.id}');
            },
            child: const Text('Create & Add Members'),
          ),
        ],
      ),
    );
  }
}

// ── Group tile ───────────────────────────────────────────────────────────────

class _GroupTile extends ConsumerWidget {
  final ContactGroup group;
  const _GroupTile({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.group)),
      title: Text(group.name),
      subtitle: Text('${group.numbers.length} member(s)'),
      // Tap → open group detail to manage members
      onTap: () => context.push('/groups/${group.id}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick-add all members as recipients
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Use as recipients',
            onPressed: group.numbers.isEmpty
                ? null
                : () {
                    ref
                        .read(recipientsProvider.notifier)
                        .addFromGroup(group.numbers,
                            groupName: group.name);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Added ${group.numbers.length} from "${group.name}"',
                        ),
                      ),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete group',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (dlg) => AlertDialog(
                  title: const Text('Delete group?'),
                  content: Text(
                      'Delete "${group.name}" and its '
                      '${group.numbers.length} member(s)?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dlg, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dlg, true),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) {
                ref.read(groupsProvider.notifier).delete(group.id);
              }
            },
          ),
        ],
      ),
    );
  }
}




