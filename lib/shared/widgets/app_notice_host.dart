import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/web_session_status.dart';
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
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(webSessionStatusProvider.notifier).check(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(appNoticeControllerProvider).current;
    final session = ref.watch(webSessionStatusProvider);
    final s = strings(ref.watch(appLanguageProvider));

    final sessionNotice = _sessionNotice(session, s);
    final effective = sessionNotice ?? notice;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: effective == null
            ? const SizedBox.shrink()
            : _NoticeOverlay(
                notice: effective,
                strings: s,
                onDismiss: () => ref
                    .read(appNoticeControllerProvider.notifier)
                    .clear(effective.id),
              ),
      ),
    );
  }

  AppNotice? _sessionNotice(WebSessionStatus status, AppStrings s) {
    if (!status.needsLogin) return null;
    final message = status.isLocked
        ? s.webLoginChallengeExceeded
        : s.webSessionBanner;
    return AppNotice(
      id: 'web-session',
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
