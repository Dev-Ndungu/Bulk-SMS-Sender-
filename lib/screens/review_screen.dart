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

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recip = ref.watch(recipientsProvider);
    final msg = ref.watch(messageProvider);
    final job = ref.watch(sendProvider);
    final isRunning = job.status == JobStatus.running;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & Send'),
        automaticallyImplyLeading: !isRunning,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Scrollable content (summary + message preview) ────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Summary card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Row('Recipients', '${recip.valid.length}'),
                          _Row('Characters', '${msg.info.charCount}'),
                          _Row('SMS segments', '${msg.info.segments}'),
                          _Row(
                            'Total SMS',
                            '${recip.valid.length * msg.info.segments}',
                          ),
                          if (msg.scheduledAt != null)
                            _Row(
                              'Scheduled',
                              msg.scheduledAt!.toLocal().toString(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Message preview — scrolls with the page, no overflow
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        msg.body.isEmpty ? '(no message)' : msg.body,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Pinned bottom panel (always visible) ──────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Progress
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

                  // Action buttons
                  if (!isRunning && job.status == JobStatus.idle)
                    FilledButton.icon(
                      onPressed: recip.valid.isNotEmpty && msg.body.isNotEmpty
                          ? () => _startSend(ref, context)
                          : null,
                      icon: const Icon(Icons.send),
                      label: const Text('Send Now'),
                    ),

                  if (isRunning)
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(sendProvider.notifier).cancel(),
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
    // Request SEND_SMS at runtime (dangerous permission)
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

    final recip = ref.read(recipientsProvider);
    final msg = ref.read(messageProvider);
    // Fire-and-forget: the async loop continues even if user navigates away.
    unawaited(ref.read(sendProvider.notifier).startSend(
          recipients: recip.valid,
          message: msg.body,
          groupName: recip.groupName,
        ));
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
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
