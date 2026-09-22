import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';

final class AppErrorState extends ConsumerWidget {
  const AppErrorState({
    required this.message,
    this.onRetry,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 32,
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null ||
                (actionLabel != null && onAction != null)) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  if (onRetry != null)
                    FilledButton.tonal(
                      onPressed: onRetry,
                      child: Text(s.retry),
                    ),
                  if (actionLabel != null && onAction != null)
                    FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
