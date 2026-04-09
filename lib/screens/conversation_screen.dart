import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/sms_message.dart';
import '../providers/inbox_provider.dart';
import '../providers/settings_provider.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  final String number;
  const ConversationScreen({super.key, required this.number});

  @override
  ConsumerState<ConversationScreen> createState() =>
      _ConversationScreenState();
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
    final msgs = await ref.read(inboxProvider.notifier)
        .getMessages(widget.number);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final subId = settingsRepo.selectedSimSubscriptionId;
    final ok = await ref.read(inboxProvider.notifier).sendReply(
          number: widget.number,
          body: text,
          subscriptionId: subId >= 0 ? subId : null,
        );
    if (mounted) {
      setState(() => _sending = false);
      if (ok) {
        _replyCtrl.clear();
        await _loadMessages(); // Reload from system
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Also listen for incoming SMS and reload
    ref.listen(inboxProvider, (_, __) => _loadMessages());

    return Scaffold(
      appBar: AppBar(title: Text(widget.number)),
      body: Column(
        children: [
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text('No messages yet. Send the first!'))
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) =>
                            _Bubble(message: _messages[i]),
                      ),
          ),
          // Reply bar
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
                        hintText: 'Type a message…',
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
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                        )
                      : IconButton(
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


// ── Chat bubble ─────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  final SmsMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isSent = message.direction == SmsDirection.sent;
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('HH:mm');

    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
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
            Text(message.body,
                style: TextStyle(
                    color: isSent
                        ? cs.onPrimaryContainer
                        : cs.onSurface)),
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
    );
  }
}
