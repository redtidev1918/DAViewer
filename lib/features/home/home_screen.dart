import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_core/dakit_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/web_session_status.dart';
import '../../core/data/da_uri.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/artwork_feed_grid.dart';
import '../../shared/widgets/skeleton.dart';
import '../notifications/notifications_providers.dart';
import 'home_feeds.dart';
import 'home_providers.dart';
import 'update_banner.dart';

/// Native home: two tabs, all rendered with the native feed UI.
///
/// - 推荐: the website-personalized `rfy/deviations` feed (web Cookie + CSRF).
/// - 每日精选: the official daily deviations (OAuth).
///
/// Deviations from watched artists live in the first-class "关注动态" tab
/// (see [WatchedFeedScreen]).
final class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final auth = ref.watch(authControllerProvider);
    final oauthSignedIn = auth.oauthSignedIn;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.appTitle),
          actions: <Widget>[
            if (oauthSignedIn)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        foregroundImage: auth.account?.avatarUri == null
                            ? null
                            : CachedNetworkImageProvider(
                                auth.account!.avatarUri.toString(),
                              ),
                        child: const Icon(Icons.person, size: 14),
                      ),
                      const SizedBox(width: 6),
                      Text(auth.account?.username ?? ''),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: FilledButton.tonal(
                    onPressed: () => context.push('/web-login'),
                    child: Text(s.login),
                  ),
                ),
              ),
            IconButton(
              tooltip: s.openLinkTooltip,
              onPressed: () => _showOpenLinkDialog(context, s),
              icon: const Icon(Icons.link),
            ),
            _NotificationsBell(),
            IconButton(
              tooltip: s.settings,
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: s.home),
              Tab(text: s.daily),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            const UpdateBanner(),
            const Expanded(
              child: TabBarView(
                children: <Widget>[PersonalizedFeed(), DailyFeed()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showOpenLinkDialog(BuildContext context, AppStrings s) async {
  final controller = TextEditingController();
  final route = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.openLinkTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: s.openLinkHint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: () {
            final link = parseDeviantArtUrl(controller.text);
            Navigator.of(context).pop(link?.route);
          },
          child: Text(s.open),
        ),
      ],
    ),
  );
  if (route != null && context.mounted) {
    unawaited(context.push(route));
  }
}

/// The website-personalized `rfy/deviations` recommendation tab. Kept public
/// so the pull-to-refresh contract can be widget-tested in isolation.
final class PersonalizedFeed extends ConsumerStatefulWidget {
  const PersonalizedFeed({super.key});

  @override
  ConsumerState<PersonalizedFeed> createState() => PersonalizedFeedState();
}

final class PersonalizedFeedState extends ConsumerState<PersonalizedFeed>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  DateTime? _backgroundedAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed || !mounted) return;

    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (backgroundedAt == null) return;

    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    final recommendedTabIsActive = DefaultTabController.of(context).index == 0;
    final scrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    if (shouldRefreshPersonalizedFeedOnResume(
      backgroundDuration: DateTime.now().difference(backgroundedAt),
      routeIsCurrent: routeIsCurrent,
      recommendedTabIsActive: recommendedTabIsActive,
      scrollOffset: scrollOffset,
    )) {
      unawaited(ref.read(personalizedFeedProvider.notifier).refreshSilently());
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final s = strings(ref.watch(appLanguageProvider));
    if (!ref.watch(webSessionReadyProvider)) {
      return const SkeletonGrid();
    }
    final feed = ref.watch(personalizedFeedProvider);
    final needsWebLogin =
        feed.error is DAKitException &&
        (feed.error! as DAKitException).code == 'web.session.unavailable';

    return ArtworkFeedGrid(
      scrollController: _scrollController,
      feed: feed,
      emptyMessage: s.noRecommendations,
      errorMessage: needsWebLogin
          ? s.recommendedSignInHint
          : s.recommendedFeedLoadFailure,
      // Pull-to-refresh goes straight to the real rfy request. A WAF-sensitive
      // home-page probe before every pull would add ~1.5s and is not an
      // authoritative logout signal; the feed request itself is the session
      // acceptance gate and carries its own CSRF refresh/retry path.
      onRefresh: () => ref.read(personalizedFeedProvider.notifier).refresh(),
      onLoadMore: () => ref.read(personalizedFeedProvider.notifier).loadMore(),
      onRetryLoadMore: () =>
          ref.read(personalizedFeedProvider.notifier).retryLoadMore(),
      errorActionLabel: needsWebLogin ? s.login : null,
      errorOnAction: needsWebLogin ? () => context.push('/web-login') : null,
    );
  }
}

const _personalizedFeedAutoRefreshAge = Duration(minutes: 10);
const _personalizedFeedTopThreshold = 120.0;

/// Automatic refresh is intentionally conservative: keep the current list
/// while another route or tab is visible, after a short app switch, or when the
/// reader has scrolled far enough that replacing the feed would be disruptive.
bool shouldRefreshPersonalizedFeedOnResume({
  required Duration backgroundDuration,
  required bool routeIsCurrent,
  required bool recommendedTabIsActive,
  required double scrollOffset,
}) {
  return backgroundDuration >= _personalizedFeedAutoRefreshAge &&
      routeIsCurrent &&
      recommendedTabIsActive &&
      scrollOffset <= _personalizedFeedTopThreshold;
}

/// The notification entry point: a bell that opens the message center and
/// shows an unread-count badge (server `isNew` minus locally read ids).
/// Signed-out users or feed failures simply show no dot.
final class _NotificationsBell extends ConsumerWidget {
  const _NotificationsBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final unread = ref.watch(notificationsUnreadCountProvider);
    final count = unread.valueOrNull ?? 0;
    return IconButton(
      tooltip: s.notifications,
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
