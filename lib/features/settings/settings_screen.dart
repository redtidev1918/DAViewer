import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_core/dakit_core.dart' hide WebSession;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/session_state.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_refresher.dart';
import '../../core/data/web_session.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/runtime/runtime_provider.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/updates/update_checker.dart';

const String _githubUrl = 'https://github.com/redtidev1918/DAViewer';
const String _releasesUrl = 'https://github.com/redtidev1918/DAViewer/releases';
const String _devartSettingsUrl =
    'https://www.deviantart.com/settings/browsing';

final class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final account = auth.account;
    final runtime = ref.watch(runtimeProvider);
    final proxy = runtime.proxyController;
    final language = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(themeModeProvider);
    final s = strings(language);
    final signedIn = auth.status == AuthStatus.signedIn;

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _AccountHeader(account: account, signedIn: signedIn, s: s),
          const SizedBox(height: 16),
          _SettingsCard(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.translate),
                title: Text(s.language),
                subtitle: Text(
                  language == AppLanguage.zh ? s.chinese : s.english,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showLanguagePicker(context, ref, language),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: Text(s.appearance),
                subtitle: Text(_themeModeLabel(themeMode, s)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showThemePicker(context, ref, themeMode),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: Text(s.proxy),
                subtitle: Text(
                  proxy?.config == null
                      ? s.directProxy
                      : '${proxy!.config!.host}:${proxy.config!.port}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/proxy'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.terminal_outlined),
                title: Text(s.diagnostics),
                subtitle: Text(s.viewLogs),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/diagnostics'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: Text(s.clearCache),
                onTap: () => _clearCache(context, s),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.system_update_outlined),
                title: Text(s.checkUpdates),
                subtitle: const Text('DAViewer · $appVersion'),
                onTap: () => _checkUpdates(context, ref, s),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(s.devartSettings),
                subtitle: Text(s.contentSettings),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => launchUrl(
                  Uri.parse(_devartSettingsUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(s.about),
                subtitle: const Text('DAViewer · $appVersion'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAbout(context, s),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.cookie_outlined),
                title: Text(s.accountCookies),
                subtitle: Text(s.accountCookiesSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAccountCookies(context, ref, s),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(signedIn ? Icons.logout : Icons.login),
                title: Text(signedIn ? s.logout : s.login),
                subtitle: signedIn ? Text(s.localLogoutHint) : null,
                onTap: () async {
                  if (signedIn) {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(s.signedOut)));
                    }
                  } else {
                    await context.push('/web-login');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(
    BuildContext context,
    WidgetRef ref,
    AppLanguage current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('中文'),
              trailing: current == AppLanguage.zh
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                ref.read(appLanguageProvider.notifier).set(AppLanguage.zh);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('English'),
              trailing: current == AppLanguage.en
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                ref.read(appLanguageProvider.notifier).set(AppLanguage.en);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) {
    final s = strings(ref.read(appLanguageProvider));
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final entry in <(ThemeMode, String)>[
              (ThemeMode.system, s.themeSystem),
              (ThemeMode.light, s.themeLight),
              (ThemeMode.dark, s.themeDark),
            ])
              ListTile(
                leading: Icon(_themeModeIcon(entry.$1)),
                title: Text(entry.$2),
                trailing: current == entry.$1 ? const Icon(Icons.check) : null,
                onTap: () {
                  ref.read(themeModeProvider.notifier).set(entry.$1);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context, AppStrings s) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.aboutDAViewer),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('DAViewer v$appVersion'),
            const SizedBox(height: 8),
            Text(s.aboutDescription),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code),
              title: Text(s.githubRepository),
              subtitle: const Text(
                'github.com/redtidev1918/DAViewer',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () async {
                await launchUrl(
                  Uri.parse(_githubUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.new_releases_outlined),
              title: Text(s.releases),
              onTap: () async {
                await launchUrl(
                  Uri.parse(_releasesUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }
}

/// A rounded card holding a related group of [ListTile]s.
final class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// The account header: avatar, username, and sign-in state.
final class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.account,
    required this.signedIn,
    required this.s,
  });

  final UserProfile? account;
  final bool signedIn;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = account?.username ?? '';
    final uri = account?.avatarUri?.toString();
    final fallback = CircleAvatar(
      radius: 28,
      child: Text(username.isEmpty ? '?' : username[0].toUpperCase()),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            if (uri == null || uri.isEmpty)
              fallback
            else
              CachedNetworkImage(
                imageUrl: uri,
                memCacheWidth: 120,
                imageBuilder: (context, imageProvider) =>
                    CircleAvatar(radius: 28, backgroundImage: imageProvider),
                placeholder: (context, url) => fallback,
                errorWidget: (context, url, error) => fallback,
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    username.isEmpty ? s.notLoggedIn : username,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    signedIn ? s.signedInWithDA : s.loginHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _themeModeLabel(ThemeMode mode, AppStrings s) => switch (mode) {
  ThemeMode.system => s.themeSystem,
  ThemeMode.light => s.themeLight,
  ThemeMode.dark => s.themeDark,
};

IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};

Future<void> _clearCache(BuildContext context, AppStrings s) async {
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  await DefaultCacheManager().emptyCache();
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.cacheCleared)));
  }
}

Future<void> _checkUpdates(
  BuildContext context,
  WidgetRef ref,
  AppStrings s,
) async {
  final dio = ref.read(runtimeProvider).dio;
  if (dio == null) return;
  try {
    final info = await fetchLatestReleaseInfo(dio: dio);
    if (!context.mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.upToDate)));
      return;
    }
    // Only compare when both sides are plain semver; a `development` build has
    // no release number to compare against, so just show the latest + download.
    final currentIsVersion = isSemver(appVersion);
    final newer =
        currentIsVersion && compareVersions(info.version, appVersion) > 0;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          newer ? s.updateDetails('v${info.version}') : s.checkUpdates,
        ),
        content: SingleChildScrollView(
          child: Text(
            newer
                ? (info.notes ?? s.noUpdateNotes)
                : currentIsVersion
                ? '${s.upToDate}（$appVersion）'
                : s.newVersionAvailable('v${info.version}'),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
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
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.upToDate)));
    }
  }
}

/// Shows the account's deviantart.com cookies: view them, copy an exportable
/// JSON snapshot, or import cookies from elsewhere. The live WebView cookies
/// are preferred; the persisted snapshot is used when the WebView store cannot
/// be read. A successful import triggers a web-session refresh so the
/// personalized feed picks it up, and — when no OAuth account is signed in —
/// offers the normal sign-in so official-API features work too.
Future<void> _showAccountCookies(
  BuildContext context,
  WidgetRef ref,
  AppStrings s,
) async {
  var cookies = await ref.read(webSessionProvider).cookies();
  if (cookies.isEmpty) {
    cookies = await ref
        .read(webSessionControllerProvider.notifier)
        .persistedCookies();
  }
  if (!context.mounted) return;
  final importedUser = await showDialog<String>(
    context: context,
    builder: (context) => _AccountCookiesDialog(cookies: cookies, s: s),
  );
  if (importedUser == null || importedUser.isEmpty) return;
  if (!context.mounted) return;
  unawaited(ref.read(webSessionRefresherProvider).refresh());
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(s.cookiesImported(importedUser))));
  // A web-only session powers the personalized feed, but official-API
  // features (follow, notifications, favourites, downloads) still need the
  // OAuth account. Offer the normal sign-in; the embedded DA page recognizes
  // the imported cookies and typically returns without asking for a password.
  final oauthSignedIn =
      ref.read(authControllerProvider).status == AuthStatus.signedIn;
  if (oauthSignedIn || !context.mounted) return;
  final goLogin = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.cookieImportNeedsOAuthTitle(importedUser)),
      content: Text(s.cookieImportNeedsOAuthBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.notNow),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(s.signInNow),
        ),
      ],
    ),
  );
  if (goLogin == true && context.mounted) {
    await context.push('/web-login');
  }
}

/// View/export/import dialog for the deviantart.com web-session cookies.
final class _AccountCookiesDialog extends ConsumerWidget {
  const _AccountCookiesDialog({required this.cookies, required this.s});

  final Map<String, String> cookies;
  final AppStrings s;

  static const TextStyle _mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>['Menlo', 'Consolas'],
    fontSize: 11,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCookies = cookies.isNotEmpty;
    final value = hasCookies ? formatCookieExport(cookies) : '';
    return AlertDialog(
      title: Text(s.accountCookies),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _WarningRow(text: s.cookiesWarning),
          const SizedBox(height: 12),
          if (hasCookies)
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: SelectableText(value, style: _mono),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.noCookiesHint,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.close),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.input, size: 18),
          label: Text(s.importCookies),
          onPressed: () async {
            final importedUser = await showDialog<String>(
              context: context,
              builder: (context) => _ImportCookiesDialog(s: s),
            );
            if (importedUser != null &&
                importedUser.isNotEmpty &&
                context.mounted) {
              Navigator.pop(context, importedUser);
            }
          },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: Text(s.copyCookies),
          onPressed: !hasCookies
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (!context.mounted) return;
                  ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(SnackBar(content: Text(s.cookiesCopied)));
                },
        ),
      ],
    );
  }
}

/// Paste-cookies dialog. Parses and imports only when the claimed identity
/// matches the current account; a different account is rejected without
/// touching the existing session (see [evaluateCookieImportIdentity]).
final class _ImportCookiesDialog extends ConsumerStatefulWidget {
  const _ImportCookiesDialog({required this.s});

  final AppStrings s;

  @override
  ConsumerState<_ImportCookiesDialog> createState() =>
      _ImportCookiesDialogState();
}

class _ImportCookiesDialogState extends ConsumerState<_ImportCookiesDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final s = widget.s;
    final parsed = parseImportedCookies(_controller.text);
    if (parsed == null || parsed.isEmpty) {
      setState(() => _error = s.cookieImportUnrecognized);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(webSessionControllerProvider.notifier)
        .importCookies(parsed);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.outcome == CookieImportOutcome.success) {
      Navigator.pop(context, result.username);
      return;
    }
    setState(() {
      _error = switch (result.outcome) {
        CookieImportOutcome.anonymous => s.cookieImportAnonymous,
        CookieImportOutcome.accountConflict => s.cookieImportConflict(
          result.username.isNotEmpty
              ? result.username
              : WebSession.usernameFromUserInfo(parsed['userinfo']),
        ),
        CookieImportOutcome.verifyFailed => s.cookieImportVerifyFailed,
        CookieImportOutcome.unavailable => s.cookieImportUnavailable,
        CookieImportOutcome.success => '',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return AlertDialog(
      title: Text(s.importCookiesTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _WarningRow(text: s.cookiesWarning),
          const SizedBox(height: 12),
          Text(s.importCookiesHint, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 8,
            minLines: 4,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: <String>['Menlo', 'Consolas'],
              fontSize: 11,
            ),
            decoration: InputDecoration(
              labelText: s.cookiesPasteLabel,
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _import,
          child: Text(_busy ? s.importing : s.importAction),
        ),
      ],
    );
  }
}

/// A warning icon with an explanatory line, used in the cookie dialogs.
final class _WarningRow extends StatelessWidget {
  const _WarningRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.warning_amber_rounded, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    );
  }
}
