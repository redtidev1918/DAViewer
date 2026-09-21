import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/web_session_status.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/notice/app_notices.dart';

/// Renders the single current application notice through Scaffold's
/// MaterialBanner. Pages never show their own persistent banners; they only
/// update [appNoticeControllerProvider] or state providers this host watches.
final class AppNoticeHost extends ConsumerStatefulWidget {
  const AppNoticeHost({super.key});

  @override
  ConsumerState<AppNoticeHost> createState() => _AppNoticeHostState();
}

final class _AppNoticeHostState extends ConsumerState<AppNoticeHost> {
  String? _renderedId;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync(context, effective, s);
    });
    return const SizedBox.shrink();
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
      action: () {
        context.push('/web-login');
      },
    );
  }

  void _sync(BuildContext context, AppNotice? notice, AppStrings s) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final id = notice?.id;
    if (id == _renderedId) return;
    messenger.hideCurrentMaterialBanner();
    if (notice == null) {
      _renderedId = null;
      return;
    }
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(notice.message),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              notice.action?.call();
            },
            child: Text(notice.actionLabel ?? s.done),
          ),
          if (notice.actionLabel == null)
            TextButton(
              onPressed: () => messenger.hideCurrentMaterialBanner(),
              child: Text(s.done),
            ),
        ],
      ),
    );
    _renderedId = id;
  }
}
