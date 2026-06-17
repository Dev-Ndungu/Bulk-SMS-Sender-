import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/sms_message.dart';
import '../providers/inbox_provider.dart';
import '../providers/settings_provider.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final String number;
  const ConversationScreen({super.key, required this.number});

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _replyCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<SmsMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    final messages =
        await ref.read(inboxProvider.notifier).getMessages(widget.number);
    if (!mounted) return;
    setState(() {
      _messages = messages;
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final subId = settingsRepo.selectedSimSubscriptionId;
    final ok = await ref.read(inboxProvider.notifier).sendReply(
          number: widget.number,
          body: text,
          subscriptionId: subId >= 0 ? subId : null,
        );

    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      _replyCtrl.clear();
      await _loadMessages();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send')),
      );
    }
  }

  Future<void> _copyMessage(SmsMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.body));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied')),
    );
  }

  Future<void> _deleteMessage(SmsMessage message) async {
    final ok = await ref.read(inboxProvider.notifier).deleteMessage(message);
    if (!mounted) return;
    if (ok) {
      setState(() => _messages.remove(message));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message deleted')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete message')),
      );
    }
  }

  Future<void> _deleteConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text('Delete all messages with ${widget.number}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final deleted =
        await ref.read(inboxProvider.notifier).deleteConversation(widget.number);
    if (!mounted) return;
    if (deleted > 0) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete conversation')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(inboxProvider, (_, __) => _loadMessages());

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.number),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'copy_number') {
                Clipboard.setData(ClipboardData(text: widget.number));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Number copied')),
                );
              } else if (value == 'delete') {
                _deleteConversation();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'copy_number',
                child: Text('Copy number'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete conversation'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet'))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (_, index) => _Bubble(
                          message: _messages[index],
                          onCopy: () => _copyMessage(_messages[index]),
                          onDelete: () => _deleteMessage(_messages[index]),
                        ),
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendReply(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                  _sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Send',
                          icon: const Icon(Icons.send),
                          onPressed: _sendReply,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final SmsMessage message;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _Bubble({
    required this.message,
    required this.onCopy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isSent = message.direction == SmsDirection.sent;
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('HH:mm');

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showActions(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSent ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isSent ? 14 : 2),
              bottomRight: Radius.circular(isSent ? 2 : 14),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                message.body,
                style: TextStyle(
                  color: isSent ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                fmt.format(message.timestamp.toLocal()),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isSent
                          ? cs.onPrimaryContainer.withValues(alpha: 0.6)
                          : cs.onSurface.withValues(alpha: 0.5),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy message'),
              onTap: () {
                Navigator.pop(sheetContext);
                onCopy();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete message'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}
