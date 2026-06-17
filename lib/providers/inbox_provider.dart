library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/hive_service.dart';
import '../models/sms_message.dart';
import '../services/sms_channel.dart';

/// A single conversation thread preview.
class ThreadPreview {
  final String number;
  final String lastBody;
  final DateTime lastTimestamp;
  final SmsDirection lastDirection;

  const ThreadPreview({
    required this.number,
    required this.lastBody,
    required this.lastTimestamp,
    required this.lastDirection,
  });
}

/// State for the inbox — conversation list.
class InboxState {
  final List<ThreadPreview> threads;
  final bool loading;

  const InboxState({this.threads = const [], this.loading = false});
}

class InboxNotifier extends Notifier<InboxState> {
  StreamSubscription<SmsMessage>? _sub;
  bool _refreshing = false;

  static const _threadsCacheKey = 'threads_cache';

  static String _messagesCacheKey(String number) => 'messages_cache:$number';

  @override
  InboxState build() {
    _listenToIncoming();
    ref.onDispose(() => _sub?.cancel());

    final cached = _readCachedThreads();

    // Seed the UI from cache immediately, then refresh in the background.
    state = InboxState(
      threads: cached,
      loading: cached.isEmpty,
    );
    unawaited(loadThreads());
    return state;
  }

  /// Load all conversation threads from the system SMS database.
  Future<void> loadThreads() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (state.threads.isEmpty) {
        state = const InboxState(loading: true);
      }

      final raw = await SmsChannel.getConversations();
      final threads = raw.map((m) => ThreadPreview(
            number: m['number'] as String,
            lastBody: m['body'] as String,
            lastTimestamp:
                DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
            lastDirection:
                (m['type'] as int) == 1 ? SmsDirection.received : SmsDirection.sent,
          )).toList();

      _cacheThreads(threads);

      if (!_sameThreads(state.threads, threads) || state.loading) {
        state = InboxState(threads: threads);
      }
    } catch (_) {
      if (state.threads.isEmpty) {
        state = const InboxState();
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Get messages for a number from the system SMS database.
  Future<List<SmsMessage>> getMessages(String number) async {
    try {
      final cached = _readCachedMessages(number);
      if (cached.isNotEmpty) {
        unawaited(_refreshMessages(number));
        return cached;
      }

      final messages = await SmsChannel.getMessagesForNumber(number);
      _cacheMessages(number, messages);
      return messages;
    } catch (_) {
      return _readCachedMessages(number);
    }
  }

  /// Send a reply via the native channel.
  Future<bool> sendReply({
    required String number,
    required String body,
    int? subscriptionId,
  }) async {
    final ok = await SmsChannel.sendSms(
      number: number,
      message: body,
      subscriptionId: subscriptionId,
    );
    if (ok) {
      // Refresh threads after sending so the new message appears
      await loadThreads();
    }
    return ok;
  }

  Future<bool> deleteMessage(SmsMessage message) async {
    final id = message.id;
    if (id == null) return false;
    final ok = await SmsChannel.deleteSmsMessage(id);
    if (ok) {
      HiveService.inbox.delete(_messagesCacheKey(message.number));
      await loadThreads();
    }
    return ok;
  }

  Future<int> deleteConversation(String number) async {
    final count = await SmsChannel.deleteConversation(number);
    if (count > 0) {
      HiveService.inbox.delete(_messagesCacheKey(number));
      await loadThreads();
    }
    return count;
  }

  /// Record a sent message — just refresh threads from system.
  Future<void> addSent({
    required String number,
    required String body,
  }) async {
    // The message was already written to content://sms/sent by the native
    // side in sendSms(), so we just need to refresh.
    // Don't do this during bulk sends — too expensive.
    // The bulk send loop will call loadThreads() once at the end.
  }

  void _listenToIncoming() {
    try {
      _sub = SmsChannel.incomingSms.listen(
        (_) {
          // Incoming SMS received — refresh threads from system
          unawaited(loadThreads());
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  Future<void> _refreshMessages(String number) async {
    try {
      final messages = await SmsChannel.getMessagesForNumber(number);
      _cacheMessages(number, messages);
    } catch (_) {}
  }

  List<ThreadPreview> _readCachedThreads() {
    final raw = HiveService.inbox.get(_threadsCacheKey);
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((m) => ThreadPreview(
              number: m['number'] as String? ?? '',
              lastBody: m['body'] as String? ?? '',
              lastTimestamp: DateTime.fromMillisecondsSinceEpoch(
                (m['timestamp'] as num?)?.toInt() ?? 0,
              ),
              lastDirection: (m['direction'] as String?) == SmsDirection.sent.name
                  ? SmsDirection.sent
                  : SmsDirection.received,
            ))
        .where((t) => t.number.isNotEmpty)
        .toList(growable: false);
  }

  void _cacheThreads(List<ThreadPreview> threads) {
    HiveService.inbox.put(
      _threadsCacheKey,
      threads
          .map(
            (t) => {
              'number': t.number,
              'body': t.lastBody,
              'timestamp': t.lastTimestamp.millisecondsSinceEpoch,
              'direction': t.lastDirection.name,
            },
          )
          .toList(growable: false),
    );
  }

  List<SmsMessage> _readCachedMessages(String number) {
    final raw = HiveService.inbox.get(_messagesCacheKey(number));
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => SmsMessage.fromMap(m))
        .toList(growable: false);
  }

  void _cacheMessages(String number, List<SmsMessage> messages) {
    HiveService.inbox.put(
      _messagesCacheKey(number),
      messages.map((m) => m.toMap()).toList(growable: false),
    );
  }

  bool _sameThreads(List<ThreadPreview> a, List<ThreadPreview> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.number != y.number ||
          x.lastBody != y.lastBody ||
          x.lastTimestamp.millisecondsSinceEpoch !=
              y.lastTimestamp.millisecondsSinceEpoch ||
          x.lastDirection != y.lastDirection) {
        return false;
      }
    }
    return true;
  }
}

final inboxProvider =
    NotifierProvider<InboxNotifier, InboxState>(InboxNotifier.new);
