import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../models/delivery_record.dart';
import '../models/recipient.dart';
import '../providers/message_provider.dart';
import '../providers/recipients_provider.dart';
import '../providers/reports_provider.dart';
import '../providers/send_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DeliveryStatus? _filter;
  /// When non-null, only records for this jobId are shown.
  String? _selectedJob;

  @override
  void initState() {
    super.initState();
    // Auto-refresh reports when the screen opens
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(reportsProvider.notifier).refresh(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(reportsProvider);

    // Group by jobId
    final jobMap = <String, List<DeliveryRecord>>{};
    for (final r in all) {
      jobMap.putIfAbsent(r.jobId, () => []).add(r);
    }
    // Sort jobs by newest first
    final jobIds = jobMap.keys.toList()
      ..sort((a, b) {
        final aTime = jobMap[a]!.first.sentAt;
        final bTime = jobMap[b]!.first.sentAt;
        return bTime.compareTo(aTime);
      });

    // If a job is selected, show that; otherwise show the job list
    final records = _selectedJob != null ? (jobMap[_selectedJob] ?? []) : all;
    final displayed =
        _filter == null ? records : records.where((r) => r.status == _filter).toList();

    final sent = records.where((r) => r.status == DeliveryStatus.sent).length;
    final failed = records.where((r) => r.status == DeliveryStatus.failed).length;
    final pending = records.where((r) => r.status == DeliveryStatus.pending).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedJob != null ? 'Campaign Report' : 'Reports'),
        leading: _selectedJob != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _selectedJob = null;
                  _filter = null;
                }),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export CSV',
            onPressed: records.isEmpty ? null : () => _exportCsv(records),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'clear') {
                await ref.read(reportsProvider.notifier).clearAll();
                setState(() => _selectedJob = null);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear all')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Metric cards ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _MetricCard('Total', '${records.length}', Colors.blue),
                _MetricCard('Sent', '$sent', Colors.green),
                _MetricCard('Failed', '$failed', Colors.red),
                _MetricCard('Pending', '$pending', Colors.orange),
              ].map((c) => Expanded(child: c)).toList(),
            ),
          ),

          // ── Retry All Failed button ─────────────────────────────────
          if (failed > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => _retryAllFailed(records),
                  icon: const Icon(Icons.replay),
                  label: Text('Retry All $failed Failed'),
                ),
              ),
            ),

          // ── Filter bar ──────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                const SizedBox(width: 8),
                ...DeliveryStatus.values.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(s.name),
                      selected: _filter == s,
                      onSelected: (_) =>
                          setState(() => _filter = _filter == s ? null : s),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Content ─────────────────────────────────────────────────
          Expanded(
            child: _selectedJob != null
                // Show individual records for selected campaign
                ? displayed.isEmpty
                    ? const Center(child: Text('No records'))
                    : ListView.builder(
                        itemCount: displayed.length,
                        itemBuilder: (_, i) =>
                            _RecordTile(record: displayed[i]),
                      )
                // Show campaign groups
                : jobIds.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bar_chart, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('No delivery records yet.'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: jobIds.length,
                        itemBuilder: (_, i) {
                          final jobId = jobIds[i];
                          final recs = jobMap[jobId]!;
                          final s = recs
                              .where((r) => r.status == DeliveryStatus.sent)
                              .length;
                          final f = recs
                              .where((r) => r.status == DeliveryStatus.failed)
                              .length;
                          final first = recs.first;
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: ListTile(
                              title: Text(
                                first.messageBody.length > 50
                                    ? '${first.messageBody.substring(0, 50)}…'
                                    : first.messageBody,
                              ),
                              subtitle: Text(
                                '${recs.length} recipients · $s sent · $f failed',
                              ),
                              trailing: Text(
                                _fmtDate(first.sentAt),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              onTap: () => setState(() {
                                _selectedJob = jobId;
                                _filter = null;
                              }),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _retryAllFailed(List<DeliveryRecord> records) async {
    final failedNumbers = records
        .where((r) => r.status == DeliveryStatus.failed)
        .map((r) => r.number)
        .toSet()
        .toList();

    if (failedNumbers.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Retry all failed?'),
        content: Text('Resend to ${failedNumbers.length} failed number(s)?'),
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
    if (ok != true || !mounted) return;

    // Get the original message from the first failed record
    final message = records
        .firstWhere((r) => r.status == DeliveryStatus.failed)
        .messageBody;

    ref.read(recipientsProvider.notifier).setFromNumbers(failedNumbers);
    ref.read(messageProvider.notifier).setBody(message);
    unawaited(ref.read(sendProvider.notifier).startSend(
          recipients:
              failedNumbers.map((n) => Recipient(e164: n)).toList(),
          message: message,
        ));
    if (mounted) context.push('/review');
  }

  Future<void> _exportCsv(List<DeliveryRecord> records) async {
    final sb = StringBuffer('number,status,sentAt,messageId,error\n');
    for (final r in records) {
      sb.writeln(
          '${r.number},${r.statusStr},${r.sentAt.toIso8601String()},'
          '${r.gatewayMessageId ?? ''},${r.errorMessage ?? ''}');
    }
    await Share.share(sb.toString(), subject: 'Delivery Report');
  }

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day}/${l.month} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

// ── Metric card ───────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricCard(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            Text(label,
                style:
                    Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Record tile ───────────────────────────────────────────────────────────────

class _RecordTile extends StatelessWidget {
  final DeliveryRecord record;
  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(record.status);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.2),
        child: Icon(_statusIcon(record.status), color: color, size: 18),
      ),
      title: Text(record.number),
      subtitle: Text(record.errorMessage ?? record.statusStr),
      trailing: Text(
        _fmt(record.sentAt),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }

  Color _statusColor(DeliveryStatus s) => switch (s) {
        DeliveryStatus.sent => Colors.green,
        DeliveryStatus.delivered => Colors.teal,
        DeliveryStatus.failed => Colors.red,
        DeliveryStatus.pending => Colors.orange,
        DeliveryStatus.unknown => Colors.grey,
      };

  IconData _statusIcon(DeliveryStatus s) => switch (s) {
        DeliveryStatus.sent => Icons.check,
        DeliveryStatus.delivered => Icons.done_all,
        DeliveryStatus.failed => Icons.error_outline,
        DeliveryStatus.pending => Icons.hourglass_empty,
        DeliveryStatus.unknown => Icons.help_outline,
      };

  String _fmt(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}
