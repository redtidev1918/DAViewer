import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_core/dakit_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/diagnostics/error_text.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_error_state.dart';
import '../../shared/widgets/app_refresh_indicator.dart';
import '../../shared/widgets/relative_time_text.dart';
import '../../shared/widgets/scrollable_fill.dart';
import '../../shared/widgets/skeleton.dart';
import '../artwork/artwork_navigation.dart';
import 'notification_read_store.dart';
import 'notifications_providers.dart';

/// The user's DeviantArt notifications (message center). Each entry shows
/// *which user* triggered the notification (the originator), what they did,
/// and the affected artwork. Tapping a notification dismisses its unread dot
/// locally; "mark all read" dismisses every current dot.
final class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

final class _NotificationsScreenState
    extends ConsumerState<NotificationsScreen> {
  Set<String> _readIds = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(
      NotificationReadStore.load().then((ids) {
        if (mounted) setState(() => _readIds = ids);
      }),
    );
  }

  Future<void> _markRead(String id) async {
    if (!_readIds.add(id)) return;
    setState(() {});
    unawaited(NotificationReadStore.add(id));
  }

  Future<void> _markAllRead(Iterable<ProviderMessage> items) async {
    final ids = items.map((message) => message.id).where((id) => id.isNotEmpty);
    final updated = await NotificationReadStore.addAll(ids);
    if (mounted) setState(() => _readIds = updated);
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(ref.watch(appLanguageProvider));
    final auth = ref.watch(authControllerProvider);
    if (auth.status != AuthStatus.signedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(s.notifications)),
        body: Center(
          child: FilledButton(
            onPressed: () => context.push('/web-login'),
            child: Text(s.login),
          ),
        ),
      );
    }
    final messages = ref.watch(notificationsProvider);
    final items = messages.value ?? const <ProviderMessage>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(s.notifications),
        actions: <Widget>[
          if (items.isNotEmpty)
            IconButton(
              tooltip: s.markAllRead,
              onPressed: () => _markAllRead(items),
              icon: const Icon(Icons.done_all),
            ),
        ],
      ),
      body: messages.when(
        loading: () => const SkeletonList(),
        error: (error, stackTrace) => AppRefreshIndicator(
          onRefresh: () => ref.refresh(notificationsProvider.future),
          child: ScrollableFill(
            child: AppErrorState(
              message: _friendlyError(error, s),
              onRetry: () => ref.invalidate(notificationsProvider),
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return AppRefreshIndicator(
              onRefresh: () => ref.refresh(notificationsProvider.future),
              child: ScrollableFill(
                child: AppEmptyState(
                  message: s.noNotifications,
                  icon: Icons.notifications_none,
                ),
              ),
            );
          }
          final notificationArtworks = <Artwork>[
            for (final message in items) ?message.artwork,
          ];
          return AppRefreshIndicator(
            onRefresh: () => ref.refresh(notificationsProvider.future),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) => _MessageTile(
                message: items[index],
                s: s,
                isRead: _readIds.contains(items[index].id),
                onTap: () => _markRead(items[index].id),
                onOpenArtwork: switch (items[index].artwork) {
                  final artwork? => () => openArtworkFromList(
                    context,
                    ref,
                    artworks: notificationArtworks,
                    artwork: artwork,
                  ),
                  null => null,
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

final class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.s,
    required this.isRead,
    required this.onTap,
    this.onOpenArtwork,
  });

  final ProviderMessage message;
  final AppStrings s;
  final bool isRead;
  final VoidCallback onTap;
  final VoidCallback? onOpenArtwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final originator = message.originator ?? message.profile;
    final artwork = message.artwork;
    final username = originator?.username ?? '';
    final thumbnail = artwork?.media.firstOrNull;
    final showNew = message.isNew && !isRead;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _Avatar(
        url: originator?.avatarUri?.toString(),
        username: username.isEmpty ? artwork?.author.username : username,
      ),
      title: Row(
        children: <Widget>[
          if (showNew) ...[
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
          Expanded(
            child: Text(
              username.isEmpty ? s.unknownUser : '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: showNew ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        s.notificationTypeLabel(message.type) +
            (artwork == null ? '' : ' · ${artwork.title}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RelativeTimeText(
            time: message.postedAt,
            format: s.relativeTime,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (thumbnail?.uri case final uri?) ...[
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: uri.toString(),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                memCacheWidth: 120,
                placeholder: (context, url) => const SizedBox(
                  width: 56,
                  height: 56,
                  child: ColoredBox(color: AppTheme.placeholderColor),
                ),
                errorWidget: (context, url, error) => const SizedBox(
                  width: 56,
                  height: 56,
                  child: ColoredBox(
                    color: AppTheme.placeholderColor,
                    child: Icon(Icons.image, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      onTap: () {
        onTap();
        if (onOpenArtwork != null) {
          onOpenArtwork!();
        } else if (originator != null && originator.username.isNotEmpty) {
          context.push('/artist/${originator.username}');
        }
      },
    );
  }
}

final class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.username});

  final String? url;
  final String? username;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      child: Text(
        (username?.isNotEmpty ?? false) ? username![0].toUpperCase() : '?',
      ),
    );
    final uri = url;
    if (uri == null || uri.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: uri,
      memCacheWidth: 120,
      imageBuilder: (context, imageProvider) =>
          CircleAvatar(backgroundImage: imageProvider),
      placeholder: (context, url) => fallback,
      errorWidget: (context, url, error) => fallback,
    );
  }
}

String _friendlyError(Object error, AppStrings s) {
  if (error is DAKitException) {
    switch (error.kind) {
      case DAKitFailureKind.authentication:
      case DAKitFailureKind.authorization:
        return s.notifPermissionError;
      default:
        break;
    }
  }
  return friendlyErrorMessage(error);
}
