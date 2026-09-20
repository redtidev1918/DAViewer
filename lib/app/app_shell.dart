import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/auth_state.dart';
import '../core/l10n/app_strings.dart';

final class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    // A fresh sign-in (signedOut -> signedIn) shows one success toast; the
    // cold-start session restore (unknown -> signedIn) stays silent.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous?.status == AuthStatus.signedOut &&
          next.status == AuthStatus.signedIn) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.loginSuccess)));
      }
    });
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: s.home,
          ),
          NavigationDestination(
            icon: const Icon(Icons.dynamic_feed_outlined),
            selectedIcon: const Icon(Icons.dynamic_feed),
            label: s.following,
          ),
          NavigationDestination(
            icon: const Icon(Icons.search),
            label: s.search,
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_outline),
            selectedIcon: const Icon(Icons.favorite),
            label: s.favourites,
          ),
          NavigationDestination(
            icon: const Icon(Icons.download_outlined),
            selectedIcon: const Icon(Icons.download),
            label: s.downloads,
          ),
        ],
      ),
    );
  }
}
