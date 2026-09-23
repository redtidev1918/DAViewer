import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/web_session_status.dart';
import '../../core/diagnostics/app_logger.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/notice/app_notices.dart';

/// Renders the current notice as an overlay at the top of the shell, so it
/// never pushes or shifts the page layout. Pages never show their own
/// persistent banners; they only update state providers this host watches.
final class AppNoticeHost extends ConsumerStatefulWidget {
  const AppNoticeHost({super.key});

  @override
  ConsumerState<AppNoticeHost> createState() => _AppNoticeHostState();
}

final class _AppNoticeHostState extends ConsumerState<AppNoticeHost> {
  final Set<String> _dismissedNoticeIds = <String>{};
  bool _loginNoticeLogged = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(webSessionStatusProvider.notifier).check(),
    );
    AppLogger.instance.info('notice', 'notice host created');
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(appNoticeControllerProvider).current;
    final session = ref.watch(webSessionStatusProvider);
    final s = strings(ref.watch(appLanguageProvider));

    // Dismissal suppresses only the current session-state occurrence. After a
    // healthy period the same state is a new occurrence and may prompt again.
    if (session.isHealthy && _dismissedNoticeIds.isNotEmpty) {
      _dismissedNoticeIds.clear();
    }

    final sessionNotice = _sessionNotice(session, s);
    if (sessionNotice != null && !_loginNoticeLogged) {
      _loginNoticeLogged = true;
      AppLogger.instance.warning(
        'notice',
        'web-session login notice shown '
            'state=${session.state.name} '
            'source=${session.serverUsername.isEmpty ? 'verdict-chain' : session.serverUsername}',
      );
    } else if (sessionNotice == null) {
      _loginNoticeLogged = false;
    }
    final visibleSessionNotice =
        sessionNotice != null && _dismissedNoticeIds.contains(sessionNotice.id)
        ? null
        : sessionNotice;
    final effective = visibleSessionNotice ?? notice;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: effective == null
            ? const SizedBox.shrink()
            : _NoticeOverlay(
                notice: effective,
                strings: s,
                onDismiss: () => _dismiss(effective, sessionNotice),
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
      setState(() => _dismissedNoticeIds.add(notice.id));
      return;
    }
    ref.read(appNoticeControllerProvider.notifier).clear(notice.id);
  }
}

final class _NoticeOverlay extends StatelessWidget {
  const _NoticeOverlay({
    required this.notice,
    required this.strings,
    required this.onDismiss,
  });

  final AppNotice notice;
  final AppStrings strings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: scheme.errorContainer,
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.info_outline,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  notice.message,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onErrorContainer),
                ),
              ),
              const SizedBox(width: 8),
              if (notice.actionLabel != null)
                TextButton(
                  onPressed: notice.action,
                  child: Text(notice.actionLabel!),
                ),
              IconButton(
                tooltip: strings.done,
                onPressed: onDismiss,
                icon: Icon(
                  Icons.close,
                  size: 16,
                  color: scheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
