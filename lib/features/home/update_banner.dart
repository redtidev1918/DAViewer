import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/updates/update_checker.dart';
import '../../shared/widgets/app_notice_card.dart';

const String _releasesUrl = 'https://github.com/redtidev1918/DAViewer/releases';

/// A slim, dismissible banner shown above the Home feed when a newer release is
/// available. It never blocks content and never re-appears for a version the
/// user has dismissed. App-level lifecycle checks run independently of Home.
final class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateCheckControllerProvider);
    if (!update.hasUpdate) return const SizedBox.shrink();
    final s = strings(ref.watch(appLanguageProvider));
    final version = update.latestVersion!;
    return SafeArea(
      bottom: false,
      child: AppNoticeCard(
        inline: true,
        message: s.newVersionAvailable('v$version'),
        actionLabel: s.viewUpdateDetails,
        onAction: () => _showUpdateDialog(context, s, version, update.notes),
        dismissLabel: s.close,
        onDismiss: () =>
            ref.read(updateCheckControllerProvider.notifier).dismiss(version),
      ),
    );
  }

  /// Shows what's new in this release before downloading: the release notes
  /// (the `RELEASE_NOTES.md` section for this version) plus a download action.
  Future<void> _showUpdateDialog(
    BuildContext context,
    AppStrings s,
    String version,
    String? notes,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.updateDetails('v$version')),
        content: SingleChildScrollView(
          child: Text(
            notes == null || notes.trim().isEmpty
                ? s.noUpdateNotes
                : notes.trim(),
            style: Theme.of(dialogContext).textTheme.bodyMedium,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              launchUrl(
                Uri.parse(_releasesUrl),
                mode: LaunchMode.externalApplication,
              );
            },
            child: Text(s.downloadUpdate),
          ),
        ],
      ),
    );
  }
}
