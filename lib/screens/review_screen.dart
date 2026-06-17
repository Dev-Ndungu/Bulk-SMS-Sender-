import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/send_job.dart';
import '../providers/message_provider.dart';
import '../providers/recipients_provider.dart';
import '../providers/reports_provider.dart';
import '../providers/send_provider.dart';
import '../providers/settings_provider.dart';
import '../services/sms_channel.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recip = ref.watch(recipientsProvider);
    final msg = ref.watch(messageProvider);
    final job = ref.watch(sendProvider);
    final isRunning = job.status == JobStatus.running;
    final canSend = recip.valid.isNotEmpty && msg.body.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & Send'),
        automaticallyImplyLeading: !isRunning,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!canSend) ...[
                    _ActionRequired(
                      hasRecipients: recip.valid.isNotEmpty,
                      hasMessage: msg.body.trim().isNotEmpty,
                    ),
                    const SizedBox(height: 16),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Row('Recipients', '${recip.valid.length}'),
                          if (recip.groupName != null)
                            _Row('Source', recip.groupName!),
                          _Row('Characters', '${msg.info.charCount}'),
                          _Row('SMS segments', '${msg.info.segments}'),
                          _Row(
                            'Total SMS',
                            '${recip.valid.length * msg.info.segments}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        msg.body.trim().isEmpty ? '(no message)' : msg.body,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isRunning ||
                      job.status == JobStatus.done ||
                      job.status == JobStatus.cancelled) ...[
                    LinearProgressIndicator(value: job.progress),
                    const SizedBox(height: 8),
                    Text(
                      '${job.processed} / ${job.total}  '
                      '(${job.sent} sent, ${job.failed} failed)',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!isRunning && job.status == JobStatus.idle)
                    FilledButton.icon(
                      onPressed: canSend ? () => _startSend(ref, context) : null,
                      icon: const Icon(Icons.send),
                      label: Text(
                        canSend
                            ? 'Send ${recip.valid.length} recipient(s)'
                            : 'Complete campaign first',
                      ),
                    ),
                  if (isRunning)
                    OutlinedButton.icon(
                      onPressed: () => ref.read(sendProvider.notifier).cancel(),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel'),
                    ),
                  if (job.status == JobStatus.done ||
                      job.status == JobStatus.cancelled) ...[
                    FilledButton.icon(
                      onPressed: () {
                        ref.read(reportsProvider.notifier).refresh();
                        context.push('/reports');
                      },
                      icon: const Icon(Icons.bar_chart),
                      label: const Text('View Report'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        ref.read(sendProvider.notifier).reset();
                        ref.read(recipientsProvider.notifier).clear();
                        ref.read(messageProvider.notifier).clear();
                        context.go('/');
                      },
                      child: const Text('New Campaign'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startSend(WidgetRef ref, BuildContext context) async {
    final recip = ref.read(recipientsProvider);
    final msg = ref.read(messageProvider);
    final message = msg.body.trim();
    if (recip.valid.isEmpty || message.isEmpty) return;

    final defaultReady = await _ensureDefaultSmsApp(context);
    if (!defaultReady) return;

    final status = await Permission.sms.request();
    if (!status.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS permission is required to send messages.'),
          ),
        );
      }
      return;
    }

    final simReady = await _ensureSimSelected(ref, context);
    if (!simReady) return;

    unawaited(
      ref.read(sendProvider.notifier).startSend(
            recipients: recip.valid,
            message: message,
            groupName: recip.groupName,
          ),
    );
  }

  Future<bool> _ensureDefaultSmsApp(BuildContext context) async {
    final isDefault = await SmsChannel.isDefaultSmsApp();
    if (isDefault) return true;
    if (!context.mounted) return false;

    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set Bulk SMS as default'),
        content: const Text(
          'To send bulk SMS reliably, set this app as the default SMS app. '
          'This helps stop Android from repeatedly asking you to allow each '
          'batch of messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set default'),
          ),
        ],
      ),
    );

    if (shouldRequest != true) return false;

    final accepted = await SmsChannel.requestDefaultSmsApp();
    if (accepted) return true;
    if (!context.mounted) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bulk SMS must be the default SMS app before sending.'),
      ),
    );
    return false;
  }

  Future<bool> _ensureSimSelected(WidgetRef ref, BuildContext context) async {
    final repo = ref.read(settingsRepositoryProvider);
    if (repo.selectedSimSubscriptionId >= 0) return true;

    final sims = await SmsChannel.getSimCards();
    final selectable = sims
        .where((sim) => sim.subscriptionId >= 0)
        .toList(growable: false);
    if (selectable.length <= 1 || !context.mounted) return true;

    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Choose sending SIM'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, -1),
            child: const ListTile(
              leading: Icon(Icons.phone_android),
              title: Text('Use device default'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          ...selectable.map(
            (sim) => SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, sim.subscriptionId),
              child: ListTile(
                leading: const Icon(Icons.sim_card),
                title: Text(sim.label),
                subtitle: sim.number.isEmpty ? null : Text(sim.number),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );

    if (selected == null) return false;
    await repo.setSelectedSimSubscriptionId(selected);
    ref.invalidate(simCardsProvider);
    return true;
  }
}

class _ActionRequired extends StatelessWidget {
  final bool hasRecipients;
  final bool hasMessage;

  const _ActionRequired({
    required this.hasRecipients,
    required this.hasMessage,
  });

  @override
  Widget build(BuildContext context) {
    final missing = [
      if (!hasRecipients) 'recipients',
      if (!hasMessage) 'message',
    ].join(' and ');
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: cs.error),
            const SizedBox(width: 12),
            Expanded(child: Text('Missing $missing')),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
