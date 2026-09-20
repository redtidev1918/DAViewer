import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/updates/update_checker.dart';

const String _releasesUrl = 'https://github.com/redtidev1918/DAViewer/releases';

/// A slim, dismissible banner shown above the Home feed when a newer release is
/// available. It never blocks content and never re-appears for a version the
/// user has dismissed. It also re-checks when the app returns to the
/// foreground, so a release published mid-session shows up on the next resume.
final class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

final class _UpdateBannerState extends ConsumerState<UpdateBanner>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(updateCheckControllerProvider.notifier).check();
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateCheckControllerProvider);
    if (!update.hasUpdate) return const SizedBox.shrink();
    final s = strings(ref.watch(appLanguageProvider));
    final theme = Theme.of(context);
    final version = update.latestVersion!;
    final color = theme.colorScheme.secondaryContainer;
    final onColor = theme.colorScheme.onSecondaryContainer;
    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () => _showUpdateDialog(context, s, version, update.notes),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: <Widget>[
                Icon(Icons.system_update_alt, size: 18, color: onColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.newVersionAvailable('v$version'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(_releasesUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(s.downloadUpdate),
                ),
                IconButton(
                  tooltip: s.close,
                  onPressed: () => ref
                      .read(updateCheckControllerProvider.notifier)
                      .dismiss(version),
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
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
