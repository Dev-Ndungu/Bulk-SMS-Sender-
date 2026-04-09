import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'services/hive_service.dart';
import 'screens/campaigns_screen.dart';
import 'screens/compose_screen.dart';
import 'screens/conversation_screen.dart';
import 'screens/group_detail_screen.dart';
import 'screens/inbox_screen.dart';
import 'screens/recipients_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/review_screen.dart';
import 'screens/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation:
      HiveService.settings.get(AppConstants.keyLastRoute, defaultValue: '/')
          as String,
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          _AppShell(location: state.matchedLocation, child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const RecipientsScreen(),
        ),
        GoRoute(
          path: '/compose',
          builder: (_, __) => const ComposeScreen(),
        ),
        GoRoute(
          path: '/review',
          builder: (_, __) => const ReviewScreen(),
        ),
        GoRoute(
          path: '/reports',
          builder: (_, __) => const ReportsScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/history',
          builder: (_, __) => const CampaignsScreen(),
        ),
        GoRoute(
          path: '/inbox',
          builder: (_, __) => const InboxScreen(),
        ),
        GoRoute(
          path: '/inbox/:number',
          builder: (_, state) => ConversationScreen(
              number: Uri.decodeComponent(state.pathParameters['number']!)),
        ),
        GoRoute(
          path: '/groups/:id',
          builder: (_, state) =>
              GroupDetailScreen(groupId: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);

class _AppShell extends StatelessWidget {
  final Widget child;
  final String location;

  const _AppShell({required this.child, required this.location});

  void _persistLocation() {
    final current = HiveService.settings.get(
      AppConstants.keyLastRoute,
      defaultValue: '/',
    ) as String;
    if (current == location) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HiveService.settings.put(AppConstants.keyLastRoute, location);
    });
  }

  int get _selectedIndex {
    if (location.startsWith('/inbox')) return 2;
    return switch (location) {
      '/' => 0,
      '/compose' => 0,
      '/review' => 0,
      '/reports' => 1,
      '/history' => 3,
      '/settings' => 4,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    _persistLocation();

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/');
            case 1:
              context.go('/reports');
            case 2:
              context.go('/inbox');
            case 3:
              context.go('/history');
            case 4:
              context.go('/settings');
          }
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Send'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Reports'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Inbox'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
