import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/campaign_summary.dart';
import '../models/delivery_record.dart';
import '../providers/campaigns_provider.dart';
import '../providers/message_provider.dart';
import '../providers/recipients_provider.dart';
import '../providers/send_provider.dart';
import '../repositories/reports_repository.dart';

class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(campaignsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (campaigns.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'clear') {
                  final ok = await _confirmClear(context);
                  if (ok && context.mounted) {
                    await ref.read(campaignsProvider.notifier).clearAll();
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'clear', child: Text('Clear all history')),
              ],
            ),
        ],
      ),
      body: campaigns.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 56, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No campaigns yet.\nSend your first message!',
                      textAlign: TextAlign.center),
                ],
              ),
            )
          : ListView.separated(
              itemCount: campaigns.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) =>
                  _CampaignTile(campaign: campaigns[i]),
            ),
    );
  }

  Future<bool> _confirmClear(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (dlg) => AlertDialog(
            title: const Text('Clear history?'),
            content: const Text('This will delete all campaign history.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dlg, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(dlg, true),
                  child: const Text('Clear')),
            ],
          ),
        ) ??
        false;
  }
}


// ── Campaign Tile ─────────────────────────────────────────────────────────────

class _CampaignTile extends ConsumerWidget {
  final CampaignSummary campaign;
  const _CampaignTile({required this.campaign});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd MMM yyyy  HH:mm');
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (campaign.groupName != null) ...[
                    Icon(Icons.group, size: 16, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(campaign.groupName!,
                        style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  Text(fmt.format(campaign.sentAt.toLocal()),
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                campaign.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: [
                  _Chip('${campaign.total} recipients',
                      Icons.people_outline, Colors.blue),
                  _Chip('${campaign.sent} sent',
                      Icons.check_circle_outline, Colors.green),
                  if (campaign.failed > 0)
                    _Chip('${campaign.failed} failed',
                        Icons.error_outline, Colors.red),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  _ActionButton(
                    icon: Icons.edit_outlined,
                    label: 'Edit & Send',
                    onTap: () => _editAndSend(context, ref),
                  ),
                  _ActionButton(
                    icon: Icons.copy_outlined,
                    label: 'Duplicate',
                    onTap: () => _duplicate(context, ref),
                  ),
                  _ActionButton(
                    icon: Icons.send_outlined,
                    label: 'Resend All',
                    color: cs.primary,
                    onTap: () => _resendNow(context, ref),
                  ),
                  if (campaign.failed > 0)
                    _ActionButton(
                      icon: Icons.replay_outlined,
                      label: 'Retry ${campaign.failed} Failed',
                      color: cs.error,
                      onTap: () => _retryFailed(context, ref),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editAndSend(BuildContext context, WidgetRef ref) {
    ref.read(recipientsProvider.notifier).setFromNumbers(
        campaign.numbers, groupName: campaign.groupName);
    ref.read(messageProvider.notifier).setBody(campaign.message);
    context.push('/compose');
  }

  void _duplicate(BuildContext context, WidgetRef ref) {
    ref.read(recipientsProvider.notifier).setFromNumbers(
        campaign.numbers, groupName: campaign.groupName);
    ref.read(messageProvider.notifier).setBody(campaign.message);
    context.push('/compose');
  }

  Future<void> _resendNow(BuildContext context, WidgetRef ref) async {
    final preview = campaign.message.length > 60
        ? '${campaign.message.substring(0, 60)}…'
        : campaign.message;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Resend campaign?'),
        content: Text(
            'Send "$preview" to ${campaign.total} recipient(s) now?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dlg, true),
              child: const Text('Send')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    _launchSend(context, ref, campaign.numbers);
  }

  Future<void> _retryFailed(BuildContext context, WidgetRef ref) async {
    // Get failed numbers from delivery records
    final repo = ReportsRepository();
    final records = repo.getByJob(campaign.id);
    final failedNumbers = records
        .where((r) => r.status == DeliveryStatus.failed)
        .map((r) => r.number)
        .toSet()
        .toList();

    if (failedNumbers.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No failed numbers to retry')),
        );
      }
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Retry failed?'),
        content: Text(
            'Resend to ${failedNumbers.length} failed number(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dlg, true),
              child: const Text('Retry')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    _launchSend(context, ref, failedNumbers);
  }

  /// Shared helper to load recipients, launch send, navigate to review.
  void _launchSend(
      BuildContext context, WidgetRef ref, List<String> numbers) {
    ref.read(recipientsProvider.notifier).setFromNumbers(numbers);
    ref.read(messageProvider.notifier).setBody(campaign.message);
    unawaited(ref.read(sendProvider.notifier).startSend(
          recipients: ref.read(recipientsProvider).valid,
          message: campaign.message,
          groupName: campaign.groupName,
        ));
    if (context.mounted) context.push('/review');
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, ctrl) =>
            _DetailSheet(campaign: campaign, scrollController: ctrl),
      ),
    );
  }
}


// ── Small reusable widgets ────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _Chip(this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: c)),
          ],
        ),
      ),
    );
  }
}

// ── Detail bottom sheet ───────────────────────────────────────────────────────

class _DetailSheet extends StatelessWidget {
  final CampaignSummary campaign;
  final ScrollController scrollController;
  const _DetailSheet(
      {required this.campaign, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd MMM yyyy  HH:mm');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Campaign Detail',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (campaign.groupName != null)
            Text('Group: ${campaign.groupName}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Sent: ${fmt.format(campaign.sentAt.toLocal())}'),
          Text('${campaign.sent} sent · ${campaign.failed} failed · '
              '${campaign.total} total'),
          const Divider(height: 20),
          Text('Message:', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(campaign.message),
          ),
          const Divider(height: 20),
          Text('Recipients (${campaign.total}):',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: campaign.numbers.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                leading: const Icon(Icons.phone, size: 16),
                title: Text(campaign.numbers[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
