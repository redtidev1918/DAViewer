import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/notice/app_notices.dart';

/// Presentation only: callers own the incident, action and dismissal policy.
/// Long messages scroll independently so actions stay available at large fonts.
final class AppNoticeCard extends StatelessWidget {
  const AppNoticeCard({
    required this.message,
    required this.onDismiss,
    required this.dismissLabel,
    this.severity = AppNoticeSeverity.info,
    this.actionLabel,
    this.onAction,
    this.inline = false,
    super.key,
  });

  final String message;
  final VoidCallback onDismiss;
  final String dismissLabel;
  final AppNoticeSeverity severity;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground, icon) = switch (severity) {
      AppNoticeSeverity.info => (
        scheme.surfaceContainerHigh,
        scheme.onSurface,
        Icons.info_outline,
      ),
      AppNoticeSeverity.warning => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.warning_amber_rounded,
      ),
      AppNoticeSeverity.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: inline ? double.infinity : 640),
        child: Material(
          color: background,
          elevation: inline ? 0 : 2,
          borderRadius: BorderRadius.circular(inline ? 0 : 12),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Icon(icon, size: 20, color: foreground),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: math.min(
                              240,
                              MediaQuery.sizeOf(context).height * .35,
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: foreground,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: dismissLabel,
                      onPressed: onDismiss,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        visualDensity: VisualDensity.standard,
                      ),
                      icon: Icon(Icons.close, size: 20, color: foreground),
                    ),
                  ],
                ),
                if (actionLabel != null && onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: onAction,
                          style: TextButton.styleFrom(
                            foregroundColor: foreground,
                            minimumSize: const Size(64, 48),
                          ),
                          child: Text(actionLabel!),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
