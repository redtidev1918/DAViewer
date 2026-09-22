import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/compact_tag_strip.dart';
import '../../shared/widgets/relative_time_text.dart';

import '../../core/l10n/app_strings.dart';
import 'artwork_access.dart';
import 'rich_html.dart';

/// The artwork title and author link, with the author's avatar for a more
/// scannable, social-style header.
final class ArtworkHeader extends StatelessWidget {
  const ArtworkHeader({required this.artwork, required this.s, super.key});

  final Artwork artwork;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = artwork.author;
    final viewLock = artworkViewLock(artwork);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(artwork.title, style: theme.textTheme.headlineSmall),
        if (viewLock != null) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Icon(
                Icons.lock_outline,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 6),
              Text(
                artworkViewLockLabel(s, viewLock),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/artist/${author.username}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  foregroundImage: author.avatarUri == null
                      ? null
                      : CachedNetworkImageProvider(author.avatarUri.toString()),
                  child: const Icon(Icons.person, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  '${s.byPrefix}${author.username}',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The artwork's publish/update dates, shown under the title as compact,
/// self-updating relative timestamps. Renders nothing when no date is known.
final class ArtworkDateSection extends StatelessWidget {
  const ArtworkDateSection({
    required this.publishedAt,
    required this.updatedAt,
    required this.s,
    super.key,
  });

  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // Only show the update time when the provider reports a real edit that is
    // later than the original publish time.
    final updated =
        updatedAt != null &&
            (publishedAt == null || updatedAt!.isAfter(publishedAt!))
        ? updatedAt
        : null;
    if (publishedAt == null && updated == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: <Widget>[
          if (publishedAt != null)
            _DateRow(
              icon: Icons.schedule,
              label: s.publishedLabel,
              time: publishedAt!,
              format: s.relativeTime,
              style: style,
            ),
          if (updated != null)
            _DateRow(
              icon: Icons.update,
              label: s.updatedLabel,
              time: updated,
              format: s.relativeTime,
              style: style,
            ),
        ],
      ),
    );
  }
}

final class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.icon,
    required this.label,
    required this.time,
    required this.format,
    required this.style,
  });

  final IconData icon;
  final String label;
  final DateTime time;
  final String Function(DateTime? time) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: 4),
        Text('$label ', style: style),
        RelativeTimeText(time: time, format: format, style: style),
      ],
    );
  }
}

/// The description / journal body, rendered as rich HTML when available and as
/// plain text otherwise. Renders nothing when there is no content.
final class ArtworkDescriptionSection extends StatelessWidget {
  const ArtworkDescriptionSection({
    required this.isJournal,
    required this.s,
    required this.onOpenLink,
    this.journalHtml,
    this.descriptionHtml,
    this.description,
    super.key,
  });

  final bool isJournal;
  final AppStrings s;
  final void Function(String? url) onOpenLink;
  final String? journalHtml;
  final String? descriptionHtml;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    if (isJournal && journalHtml != null && journalHtml!.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(s.bodyText, style: titleStyle),
          const SizedBox(height: 8),
          RichHtml(data: journalHtml!, strings: s, onLinkTap: onOpenLink),
          const SizedBox(height: 16),
        ],
      );
    }

    if (!isJournal &&
        descriptionHtml != null &&
        descriptionHtml!.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(s.description, style: titleStyle),
          const SizedBox(height: 8),
          RichHtml(data: descriptionHtml!, strings: s, onLinkTap: onOpenLink),
          const SizedBox(height: 16),
        ],
      );
    }

    if (description != null && description!.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(isJournal ? s.bodyText : s.description, style: titleStyle),
          const SizedBox(height: 8),
          SelectableText(
            description!,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

/// A compact, single-line strip of searchable tags.
final class ArtworkTagsSection extends StatelessWidget {
  const ArtworkTagsSection({required this.tags, super.key});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: CompactTagStrip(
        tags: tags,
        padding: EdgeInsets.zero,
        onSelected: (tag) => context.push('/tag/${Uri.encodeComponent(tag)}'),
      ),
    );
  }
}
