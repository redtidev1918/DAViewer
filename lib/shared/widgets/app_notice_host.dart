import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/login_observation.dart';
import '../../core/auth/web_session_status.dart';
import '../../core/diagnostics/app_logger.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/notice/app_notices.dart';
import '../../core/notice/web_session_notice.dart';
import 'app_notice_card.dart';

/// Renders the current notice as an overlay at the bottom of the page, so it
/// never pushes or shifts the page layout. Pages never show their own
/// persistent banners; they only update state providers this host watches.
final class AppNoticeHost extends ConsumerStatefulWidget {
  const AppNoticeHost({super.key});

  @override
  ConsumerState<AppNoticeHost> createState() => _AppNoticeHostState();
}

/// Mounts [child] together with [AppNoticeHost].
///
/// The host must live inside the navigator: it needs the ambient [Overlay] for
/// its tooltip and the router to open the login page. A route that pushes on
/// top of [AppShell] therefore hides the shell host, so pushed routes wrap
/// themselves in this widget instead of mounting the host above the router.
final class NoticeOverlay extends StatelessWidget {
  const NoticeOverlay({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        child,
        const Positioned(bottom: 0, left: 0, right: 0, child: AppNoticeHost()),
      ],
    );
  }
}

final class _AppNoticeHostState extends ConsumerState<AppNoticeHost> {
  bool _loginNoticeLogged = false;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.info('notice', 'notice host created');
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(appNoticeControllerProvider).current;
    final session = ref.watch(webSessionStatusProvider);
    final webObservation = ref.watch(
      loginObservationProvider(LoginChannel.web),
    );
    final apiObservation = ref.watch(
      loginObservationProvider(LoginChannel.api),
    );
    final dismissedNoticeIds = ref.watch(webSessionNoticeDismissalProvider);
    final s = strings(ref.watch(appLanguageProvider));

    // Recommendation-capability degradation (personalizedSessionStatus) is
    // deliberately NOT a host notice: it is labeled directly on the home
    // recommendations tab, attached to the content it qualifies, with retry
    // and dismissal there (P0-B, 2026-10-13).
    final sessionNotice = _sessionNotice(
      session,
      webObservation,
      apiObservation,
      dismissedNoticeIds,
      s,
    );
    if (sessionNotice != null && !_loginNoticeLogged) {
      _loginNoticeLogged = true;
      AppLogger.instance.warning(
        'notice',
        'web-session login notice shown noticeId=${sessionNotice.id} '
            'state=${session.state.name} source=verdict-chain '
            'generation=${ref.read(webSessionStatusProvider.notifier).generation}',
      );
    } else if (sessionNotice == null) {
      _loginNoticeLogged = false;
    }
    final effective = sessionNotice ?? notice;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: effective == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.all(8),
                child: AppNoticeCard(
                  message: effective.message,
                  severity: effective.severity,
                  actionLabel: effective.actionLabel,
                  onAction: effective.action,
                  dismissLabel: s.close,
                  onDismiss: () => _dismiss(effective, sessionNotice),
                ),
              ),
      ),
    );
  }

  /// The highest-priority session notice the user has not dismissed. Web
  /// invalidation outranks a challenge lock, which outranks the API channel;
  /// each channel keeps its own dismissal, so closing one still leaves the
  /// other incident readable.
  AppNotice? _sessionNotice(
    WebSessionStatus status,
    LoginObservation web,
    LoginObservation api,
    Set<String> dismissed,
    AppStrings s,
  ) {
    final candidates = <AppNotice>[];
    final webNotice = _webSessionNotice(status, web, s);
    if (webNotice != null) candidates.add(webNotice);
    final apiNotice = _apiSessionNotice(api, s);
    if (apiNotice != null) candidates.add(apiNotice);
    for (final candidate in candidates) {
      if (!dismissed.contains(candidate.id)) return candidate;
    }
    return null;
  }

  /// A definite invalidation is the only web verdict allowed to claim the
  /// sign-in expired. A challenge lock, unknown and transient verdicts never
  /// do, and a session without prior-login evidence has nothing to expire.
  AppNotice? _webSessionNotice(
    WebSessionStatus status,
    LoginObservation web,
    AppStrings s,
  ) {
    switch (status.state) {
      case WebSessionStatusState.locked:
        // The network is being challenged; the sign-in itself may still be
        // valid. Keep the challenge copy and offer verification instead.
        return AppNotice(
          id: webSessionNoticeId(web.owner, locked: true),
          message: s.webLoginChallengeExceeded,
          actionLabel: s.openWebVerificationAction,
          action: _openWebLogin,
          severity: AppNoticeSeverity.warning,
        );
      case WebSessionStatusState.stale:
        // Defensive arm: `resolveWebSessionVerdict`
        // (core/auth/web_session_verdict.dart:75-165) only transitions to
        // healthy/anonymous/unavailable/unverified, so nothing produces
        // `stale` today. Should a future producer emit it, it is a definite
        // invalidation rather than a transient answer.
        return _webSessionInvalidated(web, s);
      case WebSessionStatusState.anonymous:
        // 无登录历史不弹"已失效": only an account that signed in at some
        // point can report an expired session.
        return web.lastSuccess == null ? null : _webSessionInvalidated(web, s);
      case WebSessionStatusState.unknown:
      case WebSessionStatusState.unverified:
      case WebSessionStatusState.unavailable:
      case WebSessionStatusState.healthy:
        return null;
    }
  }

  AppNotice _webSessionInvalidated(LoginObservation web, AppStrings s) =>
      AppNotice(
        id: webSessionNoticeId(web.owner, locked: false),
        message: s.webSessionInvalidated,
        actionLabel: s.webSessionReloginAction,
        action: _openWebLogin,
        severity: AppNoticeSeverity.warning,
      );

  /// The API (OAuth) channel is its own incident with its own copy and
  /// dismissal, and it reuses the one existing login entry point.
  AppNotice? _apiSessionNotice(LoginObservation api, AppStrings s) {
    if (api.result != LoginCheckResult.unauthenticated ||
        api.lastSuccess == null) {
      return null;
    }
    return AppNotice(
      id: apiSessionNoticeId(api.owner),
      message: s.apiSessionInvalidated,
      actionLabel: s.apiSessionReauthorizeAction,
      action: _openApiLogin,
      severity: AppNoticeSeverity.warning,
    );
  }

  void _openWebLogin() {
    if (!mounted || !ref.read(webSessionStatusProvider).needsLogin) return;
    _pushLogin();
  }

  /// The API reminder reuses the one route that can re-authorize. Linkage to
  /// document: opening `/web-login` runs `beginInteractiveRecovery()`
  /// (lib/features/web_login/web_login_screen.dart:103), which flips the WEB
  /// verdict to `unverified` and bumps its generation
  /// (lib/core/auth/web_session_status.dart:197-208) — so the web reminder
  /// hides while the login screen is open and an in-flight web check is
  /// dropped without a verdict. Nothing is logged out and no Cookie is
  /// cleared; `endInteractiveRecovery()` releases the interactive state.
  void _openApiLogin() {
    if (!mounted) return;
    final api = ref.read(loginObservationProvider(LoginChannel.api));
    if (api.result != LoginCheckResult.unauthenticated) return;
    _pushLogin();
  }

  void _pushLogin() {
    // One entry point for both channels: /web-login hosts the WebView that
    // establishes the web Cookie/CSRF session and the OAuth account in a single
    // login (lib/core/auth/webview_oauth_bridge.dart:8-15). Starting the
    // authorize from the notice instead would race the route push: the bridge
    // falls back to the system browser after a 500 ms grace period
    // (webview_oauth_bridge.dart:48-50), and that browser does not write the
    // embedded WebView's cookie store.
    GoRouter.of(context).push('/web-login');
  }

  void _dismiss(AppNotice notice, AppNotice? sessionNotice) {
    if (identical(notice, sessionNotice)) {
      ref.read(webSessionNoticeDismissalProvider.notifier).dismiss(notice.id);
      return;
    }
    ref.read(appNoticeControllerProvider.notifier).clear(notice.id);
  }
}
