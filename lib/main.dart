import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_theme.dart';
import 'router.dart';
import 'providers/campaigns_provider.dart';
import 'providers/inbox_provider.dart';
import 'providers/reports_provider.dart';
import 'services/bulk_send_sync_service.dart';
import 'services/hive_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveService.init();
  runApp(const ProviderScope(child: _BootstrapApp()));
}

class _BootstrapApp extends ConsumerStatefulWidget {
  const _BootstrapApp();

  @override
  ConsumerState<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends ConsumerState<_BootstrapApp>
    with WidgetsBindingObserver {
  bool _syncing = false;
  late final Future<void> _initialRestore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialRestore = _syncPendingState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncPendingState());
    }
  }

  Future<void> _syncPendingState() async {
    if (_syncing || !mounted) return;
    _syncing = true;
    try {
      await BulkSendSyncService.syncAllPending();
      if (!mounted) return;
      ref.read(campaignsProvider.notifier).refresh();
      ref.read(reportsProvider.notifier).refresh();
      ref.read(inboxProvider.notifier).loadThreads();
    } catch (_) {
      // Best effort: the native job continues even if the sync fails.
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialRestore,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Restoring send history...',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const BulkSmsApp();
      },
    );
  }
}

class BulkSmsApp extends StatelessWidget {
  const BulkSmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Bulk SMS Kenya',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
