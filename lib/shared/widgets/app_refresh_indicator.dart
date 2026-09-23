import 'package:flutter/material.dart';

/// The app's pull-to-refresh, styled consistently across screens: theme-primary
/// spinner on a surface background with a comfortable displacement.
final class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    required this.onRefresh,
    required this.child,
    super.key,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: scheme.primary,
      backgroundColor: scheme.surface,
      strokeWidth: 2.5,
      displacement: 48,
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      child: child,
    );
  }
}
