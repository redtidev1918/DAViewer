import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/diagnostics/app_logger.dart';
import '../../core/notice/app_notices.dart';

export '../../core/notice/app_notices.dart' show AppNoticeSeverity;

final _activeFeedback = Expando<_Feedback>('active operation feedback');

final class _Feedback {
  _Feedback(
    this.message,
    this.severity,
    this.source,
    this.hasAction,
    this.route,
  );
  final String message;
  final AppNoticeSeverity severity;
  final String source;
  final bool hasAction;
  final ModalRoute<dynamic>? route;
}

/// Short-lived feedback for an operation, never an authentication verdict.
/// Repeated visible results coalesce; a different result replaces stale queued
/// feedback. State-bound notices stay with their existing providers/hosts.
void showFeedback(
  BuildContext context,
  String message, {
  required String source,
  AppNoticeSeverity severity = AppNoticeSeverity.info,
  SnackBarAction? action,
  ScaffoldMessengerState? messenger,
}) {
  void show() {
    if (!context.mounted) return;
    // Kept-alive tab/route contexts can complete work after becoming hidden.
    final route = ModalRoute.of(context);
    if (!TickerMode.valuesOf(context).enabled || route?.isCurrent == false) {
      return;
    }
    final host = messenger ?? ScaffoldMessenger.maybeOf(context);
    if (host == null || !host.mounted) return;
    final previous = _activeFeedback[host];
    if (previous?.message == message &&
        previous?.severity == severity &&
        previous?.source == source &&
        previous?.hasAction == (action != null) &&
        identical(previous?.route, route)) {
      return;
    }
    final entry = _Feedback(message, severity, source, action != null, route);
    final colors = Theme.of(context).colorScheme;
    final foreground = switch (severity) {
      AppNoticeSeverity.info => null,
      AppNoticeSeverity.warning => colors.onSecondaryContainer,
      AppNoticeSeverity.error => colors.onErrorContainer,
    };
    host.clearSnackBars();
    final handle = host.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: foreground == null ? null : TextStyle(color: foreground),
        ),
        action: action == null
            ? null
            : SnackBarAction(
                label: action.label,
                textColor: foreground ?? action.textColor,
                onPressed: () {
                  if (context.mounted &&
                      route?.isCurrent != false &&
                      TickerMode.valuesOf(context).enabled) {
                    action.onPressed();
                  }
                },
              ),
        showCloseIcon: true,
        duration: Duration(seconds: severity == AppNoticeSeverity.info ? 4 : 6),
        backgroundColor: severity == AppNoticeSeverity.error
            ? colors.errorContainer
            : severity == AppNoticeSeverity.warning
            ? colors.secondaryContainer
            : null,
        closeIconColor: severity == AppNoticeSeverity.error
            ? colors.onErrorContainer
            : severity == AppNoticeSeverity.warning
            ? colors.onSecondaryContainer
            : null,
      ),
    );
    _activeFeedback[host] = entry;
    handle.closed.then((_) {
      if (identical(_activeFeedback[host], entry)) _activeFeedback[host] = null;
    });
    // Never log message text: it may contain a filename, account or error URL.
    AppLogger.instance.info(
      'notice',
      'feedback source=$source severity=${severity.name} event=shown',
    );
  }

  // Provider listeners may fire during build. Defer only within an active
  // frame; an idle callback must not wait for a frame that may never arrive.
  if (SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks) {
    WidgetsBinding.instance.addPostFrameCallback((_) => show());
  } else {
    show();
  }
}
