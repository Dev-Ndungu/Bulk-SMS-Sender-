import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/settings_provider.dart';
import '../repositories/settings_repository.dart';
import '../services/sms_channel.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final SettingsRepository _repo;
  List<SimCard> _sims = [];
  bool _isDefaultSms = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(settingsRepositoryProvider);
    _loadSims();
    _checkDefaultSms();
  }

  Future<void> _loadSims() async {
    await Permission.phone.request();
    final sims = await SmsChannel.getSimCards();
    if (!mounted) return;
    setState(() => _sims = sims);
  }

  Future<void> _checkDefaultSms() async {
    final isDefault = await SmsChannel.isDefaultSmsApp();
    if (!mounted) return;
    setState(() => _isDefaultSms = isDefault);
  }

  Future<void> _requestDefaultSms() async {
    final ok = await SmsChannel.requestDefaultSmsApp();
    if (!mounted) return;
    setState(() => _isDefaultSms = ok);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bulk SMS is now the default SMS app')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = _repo.selectedSimSubscriptionId;
    final batchSize = _repo.batchSize;
    final delayMs = _repo.interSmsDelayMs;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Default SMS app ────────────────────────────────────────────
          Card(
            color: _isDefaultSms
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    _isDefaultSms ? Icons.check_circle : Icons.warning_amber,
                    color: _isDefaultSms
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isDefaultSms
                              ? 'Default SMS app ✓'
                              : 'Not the default SMS app',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isDefaultSms
                              ? 'Bulk sending works without popups.'
                              : 'Set as default to avoid the "sending too many SMS" popup.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!_isDefaultSms)
                    FilledButton(
                      onPressed: _requestDefaultSms,
                      child: const Text('Set'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── SIM selection ─────────────────────────────────────────────
          const _SectionHeader('SIM Card for Sending'),
          if (_sims.isEmpty)
            Row(
              children: [
                const Icon(Icons.sim_card, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Loading SIMs… (grant Phone permission)')),
                IconButton(
                    icon: const Icon(Icons.refresh), onPressed: _loadSims),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: DropdownMenu<int>(
                label: const Text('Send with SIM'),
                leadingIcon: const Icon(Icons.sim_card),
                initialSelection: selectedId,
                dropdownMenuEntries: [
                  const DropdownMenuEntry(
                      value: -1, label: 'Device default'),
                  ..._sims.map(
                    (sim) => DropdownMenuEntry(
                      value: sim.subscriptionId,
                      label: sim.label,
                      leadingIcon: const Icon(Icons.sim_card_outlined),
                    ),
                  ),
                ],
                onSelected: (v) async {
                  if (v == null) return;
                  await _repo.setSelectedSimSubscriptionId(v);
                  ref.invalidate(simCardsProvider);
                  setState(() {});
                },
              ),
            ),

          const Divider(height: 32),
          const _SectionHeader('Sending Speed'),

          // ── Inter-SMS delay ───────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Delay between messages'),
            subtitle: Text('$delayMs ms'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final val = await _intPicker(context,
                  title: 'Delay (ms)', initial: delayMs, min: 0, max: 5000, step: 50);
              if (val != null) {
                await _repo.setInterSmsDelayMs(val);
                setState(() {});
              }
            },
          ),

          // ── Batch size ────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.layers_outlined),
            title: const Text('Batch size'),
            subtitle: Text('$batchSize messages per pause'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final val = await _intPicker(context,
                  title: 'Batch size', initial: batchSize, min: 1, max: 500);
              if (val != null) {
                await _repo.setBatchSize(val);
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  Future<int?> _intPicker(
    BuildContext context, {
    required String title,
    required int initial,
    required int min,
    required int max,
    int step = 1,
  }) {
    int current = initial;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: current > min
                    ? () => set(() => current = (current - step).clamp(min, max))
                    : null,
              ),
              Text('$current',
                  style: Theme.of(ctx).textTheme.headlineMedium),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: current < max
                    ? () => set(() => current = (current + step).clamp(min, max))
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, current),
                child: const Text('OK')),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
