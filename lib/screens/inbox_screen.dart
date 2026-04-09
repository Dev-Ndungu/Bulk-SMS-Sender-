import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/sms_message.dart';
import '../providers/inbox_provider.dart';

class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final threads = inbox.threads;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(inboxProvider.notifier).loadThreads(),
          ),
        ],
      ),
      // FAB for new conversation
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startNewChat(context),
        child: const Icon(Icons.chat_outlined),
      ),
      body: inbox.loading && threads.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : threads.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'No conversations yet.\n'
                        'Send messages and receive replies here.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(inboxProvider.notifier).loadThreads(),
                  child: ListView.separated(
                    itemCount: threads.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = threads[i];
                      final fmt = DateFormat('dd/MM HH:mm');
                      final isReceived =
                          t.lastDirection == SmsDirection.received;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            t.number.length >= 2
                                ? t.number.substring(t.number.length - 2)
                                : t.number,
                          ),
                        ),
                        title: Text(t.number),
                        subtitle: Row(
                          children: [
                            if (!isReceived)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.call_made,
                                    size: 12, color: Colors.grey),
                              ),
                            Expanded(
                              child: Text(
                                t.lastBody,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        trailing: Text(
                          fmt.format(t.lastTimestamp.toLocal()),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        onTap: () => context.push(
                            '/inbox/${Uri.encodeComponent(t.number)}'),
                      );
                    },
                  ),
                ),
    );
  }

  void _startNewChat(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('New conversation'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '+254712345678',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                final number = ctrl.text.trim();
                if (number.isNotEmpty) {
                  Navigator.pop(dlg);
                  context.push('/inbox/${Uri.encodeComponent(number)}');
                }
              },
              child: const Text('Chat')),
        ],
      ),
    );
  }
}
