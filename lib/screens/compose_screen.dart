import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/sms_calculator.dart';
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
    _bodyCtrl = TextEditingController(text: ref.read(messageProvider).body);
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msgState = ref.watch(messageProvider);
    final recipState = ref.watch(recipientsProvider);
    final recipCount = recipState.valid.length;
    final info = msgState.info;
    final canReview = msgState.body.trim().isNotEmpty && recipCount > 0;
    final hasNameTag = msgState.body.contains('{{name}}');
    final hasRecipientNames = recipState.valid.any(
      (recipient) => (recipient.displayName ?? '').trim().isNotEmpty,
    );

    if (_bodyCtrl.text != msgState.body) {
      _bodyCtrl.text = msgState.body;
      _bodyCtrl.selection = TextSelection.collapsed(
        offset: _bodyCtrl.text.length,
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Compose Message'),
        actions: [
          TextButton(
            onPressed: canReview ? () => context.push('/review') : null,
            child: const Text('Review'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RecipientsTile(
              count: recipCount,
              source: recipState.groupName,
              onTap: () => context.push('/'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bodyCtrl,
              minLines: 5,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Message body',
                hintText: 'Type the SMS message',
                helperText: 'Use {{name}} or {{phone}} when recipient data exists.',
                alignLabelWithHint: true,
              ),
              onChanged: (value) =>
                  ref.read(messageProvider.notifier).setBody(value),
            ),
            const SizedBox(height: 8),
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
            if (info.isUnicode) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _removeUnicode(msgState.body),
                icon: const Icon(Icons.text_format),
                label: const Text('Remove Unicode'),
              ),
            ],
            const SizedBox(height: 16),
            const Wrap(
              spacing: 8,
              children: [
                _MergeTagChip('{{name}}'),
                _MergeTagChip('{{phone}}'),
              ],
            ),
            if (hasNameTag && !hasRecipientNames) ...[
              const SizedBox(height: 12),
              _WarningPanel(
                text:
                    '{{name}} is in the message, but selected recipients do not have saved names.',
              ),
            ],
            const Divider(height: 32),
            OutlinedButton.icon(
              onPressed: msgState.body.trim().isNotEmpty
                  ? () => _showPreview(context, msgState.body)
                  : null,
              icon: const Icon(Icons.preview),
              label: const Text('Preview'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: canReview ? () => context.push('/review') : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                canReview
                    ? 'Review $recipCount recipient(s)'
                    : recipCount == 0
                        ? 'Add recipients first'
                        : 'Type a message first',
              ),
            ),
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
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _removeUnicode(String body) {
    final cleaned = SmsCalculator.removeUnicode(body);
    ref.read(messageProvider.notifier).setBody(cleaned);
  }
}

class _WarningPanel extends StatelessWidget {
  final String text;

  const _WarningPanel({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: cs.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: cs.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipientsTile extends StatelessWidget {
  final int count;
  final String? source;
  final VoidCallback onTap;

  const _RecipientsTile({
    required this.count,
    required this.source,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasRecipients = count > 0;
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      tileColor: cs.surfaceContainerHighest,
      leading: Icon(
        hasRecipients ? Icons.check_circle : Icons.people_outline,
        color: hasRecipients ? cs.primary : cs.outline,
      ),
      title: Text(
        hasRecipients
            ? '$count recipient(s) selected'
            : 'No recipients selected',
      ),
      subtitle: source == null ? null : Text(source!),
      trailing: TextButton(
        onPressed: onTap,
        child: Text(hasRecipients ? 'Edit' : 'Add'),
      ),
      onTap: onTap,
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
