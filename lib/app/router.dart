import 'package:dakit_flutter/dakit_flutter.dart' hide Page;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_controller.dart';
import '../core/auth/auth_state.dart';
import '../core/auth/web_session_status.dart';
import '../core/l10n/app_strings.dart';
import '../shared/route_observer.dart';
import '../features/artist/artist_screen.dart';
import '../features/artist/folder_screen.dart';
import '../features/artwork/artwork_detail_screen.dart';
import '../features/artwork/artwork_navigation.dart';
import '../features/diagnostics/diagnostics_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/favourites/favourites_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/proxy_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/tag/tag_screen.dart';
import '../features/watching/watching_screen.dart';
import '../features/watched/watched_feed_screen.dart';
import '../features/web_login/web_login_screen.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authRevision = ValueNotifier<int>(0);
  ref.listen(webSessionReadyProvider, (_, _) => authRevision.value++);
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: authRevision,
    observers: <NavigatorObserver>[routeObserver],
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/web-login',
        builder: (context, state) => const WebLoginScreen(),
      ),
      GoRoute(path: '/artwork/:id', pageBuilder: artworkDetailPage),
      GoRoute(
        path: '/artist/:username',
        builder: (context, state) =>
            ArtistScreen(username: state.pathParameters['username']!),
      ),
      GoRoute(
        path: '/artist/:username/folder/:folderId',
        builder: (context, state) {
          final s = strings(
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(appLanguageProvider),
          );
          return FolderScreen(
            username: state.pathParameters['username']!,
            folderId: state.pathParameters['folderId']!,
            folderName: state.uri.queryParameters['name'] ?? s.folder,
            kind: state.uri.queryParameters['kind'] == 'collection'
                ? FolderKind.collection
                : FolderKind.gallery,
          );
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'proxy',
            builder: (context, state) => const ProxySettingsScreen(),
          ),
          GoRoute(
            path: 'diagnostics',
            builder: (context, state) => const DiagnosticsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/watching',
        builder: (context, state) => const WatchingScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/tag/:tag',
        builder: (context, state) =>
            TagScreen(tag: state.pathParameters['tag']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/watch',
                builder: (context, state) => const WatchedFeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/favourites',
                builder: (context, state) => const FavouritesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/downloads',
                builder: (context, state) => const DownloadsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      // Stay on Splash until the persisted Web Session snapshot has been
      // restored; redirecting earlier disposes Splash mid-initialization and
      // can leave webSessionReady=false forever, which blocks Home entirely.
      if (state.matchedLocation == '/splash' &&
          !ref.read(webSessionReadyProvider)) {
        return null;
      }
      final auth = ref.read(authControllerProvider);
      return authRedirect(auth.status, state.matchedLocation);
    },
  );

  ref.listen(authControllerProvider, (_, _) => authRevision.value++);
  ref.onDispose(authRevision.dispose);
  ref.onDispose(router.dispose);
  return router;
});

/// Builds an artwork route with a direction-aware shared-axis transition.
/// Exposed for a router-level regression test of repeated replacements.
Page<void> artworkDetailPage(BuildContext context, GoRouterState state) {
  final artworkId = state.pathParameters['id']!;
  final routeContext = ArtworkRouteContext.fromExtra(state.extra);
  return CustomTransitionPage<void>(
    key: artworkRoutePageKey(state.pageKey, artworkId),
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    child: ArtworkDetailScreen(
      key: artworkPageKey(artworkId),
      artworkId: artworkId,
      username: state.uri.queryParameters['username'],
      browseSession: routeContext?.session,
    ),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final entrance = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0.72, end: 1).animate(entrance),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: artworkTransitionBegin(routeContext?.direction),
            end: Offset.zero,
          ).animate(entrance),
          child: child,
        ),
      );
    },
  );
}

/// Keeps first-run authentication separate from authenticated feed loading.
/// Exposed as a pure function so this critical route policy is regression
/// tested without constructing a platform WebView.
String? authRedirect(AuthStatus status, String location) {
  if (status == AuthStatus.unknown) return '/splash';
  if (status == AuthStatus.signedIn && location == '/splash') {
    return '/';
  }
  // A first-run user should see the actual sign-in flow, never a home-feed
  // request or error state. Explicit logout still lands on public Home through
  // the general signed-out redirect below.
  if (status == AuthStatus.signedOut && location == '/splash') {
    return '/web-login';
  }
  // Home remains available after the user dismisses sign-in or logs out. The
  // watched tab also stays reachable so it can show its own prompt.
  if (status != AuthStatus.signedIn && !isSignedOutRoute(location)) {
    return '/';
  }
  return null;
}

/// Login is required for account data, never for recovery and product info.
/// Settings includes proxy, diagnostics, update checking and About, all of
/// which must remain reachable when authentication itself is broken.
bool isSignedOutRoute(String location) =>
    location == '/' ||
    location == '/watch' ||
    location == '/web-login' ||
    location == '/history' ||
    location == '/settings' ||
    location.startsWith('/settings/');
