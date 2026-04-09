import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../providers/message_provider.dart';
import '../providers/recipients_provider.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final TextEditingController _bodyCtrl;

  @override
  void initState() {
    super.initState();
    _bodyCtrl =
        TextEditingController(text: ref.read(messageProvider).body);
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgState = ref.watch(messageProvider);
    final info = msgState.info;
    final recipCount = ref.watch(recipientsProvider).valid.length;

    // Keep TextEditingController in sync when provider changes from outside
    // (e.g. merge tag chips, or history pre-fill).
    if (_bodyCtrl.text != msgState.body) {
      _bodyCtrl.text = msgState.body;
      // Move cursor to end
      _bodyCtrl.selection = TextSelection.collapsed(
          offset: _bodyCtrl.text.length);
    }

    return Scaffold(
      // Let Flutter shrink the body when the keyboard appears.
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Compose Message'),
        actions: [
          TextButton(
            onPressed: msgState.body.isNotEmpty && recipCount > 0
                ? () => context.push('/review')
                : null,
            child: const Text('Review'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        // Keeps content above the keyboard without overflowing.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Body ──────────────────────────────────────────────────────
            TextField(
              controller: _bodyCtrl,
              minLines: 5,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Message body',
                hintText: 'Type your message. Use {{name}} for merge tags.',
                alignLabelWithHint: true,
              ),
              onChanged: (v) =>
                  ref.read(messageProvider.notifier).setBody(v),
            ),
            const SizedBox(height: 8),

            // ── Counter row ───────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _CounterChip(
                  label: '${info.charCount} chars',
                  color: Colors.blueGrey,
                ),
                _CounterChip(
                  label: '${info.segments} SMS',
                  color: info.segments > 1 ? Colors.orange : Colors.green,
                ),
                _CounterChip(
                  label: '${info.remaining} left',
                  color: Colors.grey,
                ),
                if (info.isUnicode)
                  Chip(
                    label: const Text('Unicode'),
                    backgroundColor:
                        Theme.of(context).colorScheme.tertiaryContainer,
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Merge tag helpers ─────────────────────────────────────────
            const Wrap(
              spacing: 8,
              children: [
                _MergeTagChip('{{name}}'),
                _MergeTagChip('{{phone}}'),
              ],
            ),
            const Divider(height: 32),

            // ── Schedule ─────────────────────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Schedule send'),
              subtitle: Text(
                msgState.scheduledAt == null
                    ? 'Send immediately'
                    : DateFormat('d MMM yyyy HH:mm')
                        .format(msgState.scheduledAt!),
              ),
              trailing: msgState.scheduledAt != null
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          ref.read(messageProvider.notifier).setSchedule(null),
                    )
                  : null,
              onTap: () async {
                final now = DateTime.now();
                final date = await showDatePicker(
                  context: context,
                  initialDate: now,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (date == null || !context.mounted) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (time == null) return;
                ref.read(messageProvider.notifier).setSchedule(
                      DateTime(date.year, date.month, date.day,
                          time.hour, time.minute),
                    );
              },
            ),
            const Divider(),

            // ── Preview button ────────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: msgState.body.isNotEmpty
                  ? () => _showPreview(context, msgState.body)
                  : null,
              icon: const Icon(Icons.preview),
              label: const Text('Preview'),
            ),
            // Extra padding so the last button clears the keyboard.
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showPreview(BuildContext context, String body) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Message Preview'),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

class _CounterChip extends StatelessWidget {
  final String label;
  final Color color;
  const _CounterChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      padding: EdgeInsets.zero,
    );
  }
}

class _MergeTagChip extends ConsumerWidget {
  final String tag;
  const _MergeTagChip(this.tag);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ActionChip(
      label: Text(tag),
      onPressed: () {
        final current = ref.read(messageProvider).body;
        ref.read(messageProvider.notifier).setBody('$current$tag');
      },
    );
  }
}
