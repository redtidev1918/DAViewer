import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final dismissedNoticeIds = ref.watch(webSessionNoticeDismissalProvider);
    final s = strings(ref.watch(appLanguageProvider));

    // Recommendation-capability degradation (personalizedSessionStatus) is
    // deliberately NOT a host notice: it is labeled directly on the home
    // recommendations tab, attached to the content it qualifies, with retry
    // and dismissal there (P0-B, 2026-10-13).
    final sessionNotice = _sessionNotice(session, s);
    if (sessionNotice != null && !_loginNoticeLogged) {
      _loginNoticeLogged = true;
      AppLogger.instance.warning(
        'notice',
        'web-session login notice shown state=${session.state.name} '
            'source=verdict-chain',
      );
    } else if (sessionNotice == null) {
      _loginNoticeLogged = false;
    }
    final visibleSessionNotice =
        sessionNotice != null && dismissedNoticeIds.contains(sessionNotice.id)
        ? null
        : sessionNotice;
    final effective = visibleSessionNotice ?? notice;
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

  AppNotice? _sessionNotice(WebSessionStatus status, AppStrings s) {
    if (!status.needsLogin) return null;
    final id = 'web-session-${status.state.name}';
    final message = status.isLocked
        ? s.webLoginChallengeExceeded
        : s.webSessionBanner;
    return AppNotice(
      id: id,
      message: message,
      actionLabel: s.login,
      action: _openWebLogin,
      severity: AppNoticeSeverity.warning,
    );
  }

  void _openWebLogin() {
    // The session notice uses the shell context; the router is available at
    // the root, so routing through the context captured by the state is safe.
    final router = GoRouter.of(context);
    router.push('/web-login');
  }

  void _dismiss(AppNotice notice, AppNotice? sessionNotice) {
    if (identical(notice, sessionNotice)) {
      ref.read(webSessionNoticeDismissalProvider.notifier).dismiss(notice.id);
      return;
    }
    ref.read(appNoticeControllerProvider.notifier).clear(notice.id);
  }
}
