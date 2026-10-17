import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/filtering/content_filter_provider.dart';
import '../../core/filtering/content_rules.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/app_error_state.dart';
import '../../shared/widgets/app_feedback.dart';

final class ContentBlocksScreen extends ConsumerStatefulWidget {
  const ContentBlocksScreen({super.key});
  @override
  ConsumerState<ContentBlocksScreen> createState() =>
      _ContentBlocksScreenState();
}

final class _ContentBlocksScreenState
    extends ConsumerState<ContentBlocksScreen> {
  bool _saving = false;
  Future<void> _save(ContentRules Function(ContentRules) update) async {
    setState(() => _saving = true);
    try {
      await ref.read(contentRulesProvider.notifier).changeRules(update);
    } on Object {
      if (mounted) {
        showFeedback(
          context,
          strings(ref.read(appLanguageProvider)).blockSaveFailed,
          source: 'content-blocks',
          severity: AppNoticeSeverity.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add(int kind) async {
    final s = strings(ref.read(appLanguageProvider));
    var raw = '';
    String? error;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final value = kind == 0
                ? normalizeTag(raw)
                : kind == 1
                ? normalizeArtist(raw)
                : artworkBlockKey(raw);
            if (value.isEmpty ||
                (kind == 0 && RegExp(r'[\s/#]').hasMatch(value)) ||
                (kind == 1 && !RegExp(r'^[a-z0-9_-]+$').hasMatch(value))) {
              setDialogState(() => error = s.invalidBlock);
              return;
            }
            Navigator.pop(context, value);
          }

          return AlertDialog(
            title: Text(
              [s.blockedTags, s.blockedArtists, s.blockedArtworks][kind],
            ),
            content: TextField(
              onChanged: (value) => raw = value,
              autofocus: true,
              decoration: InputDecoration(
                hintText: [
                  s.blockTagHint,
                  s.blockArtistHint,
                  s.blockArtworkHint,
                ][kind],
                errorText: error,
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s.cancel),
              ),
              FilledButton(onPressed: submit, child: Text(s.addBlock)),
            ],
          );
        },
      ),
    );
    if (value == null || !mounted) return;
    await _save(
      (r) => switch (kind) {
        0 => r.copyWith(tags: {...r.tags, value}),
        1 => r.copyWith(artists: {...r.artists, value}),
        _ => r.copyWith(artworks: {...r.artworks, value: value}),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(ref.watch(appLanguageProvider));
    final state = ref.watch(contentRulesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.contentBlocks)),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => AppErrorState(
          message: s.blockLoadFailed,
          onRetry: () => ref.invalidate(contentRulesProvider),
        ),
        data: (rules) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.contentBlocksScope),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.hideAi),
              subtitle: Text(s.hideAiHint),
              value: rules.hideAi,
              onChanged: _saving
                  ? null
                  : (value) => _save((r) => r.copyWith(hideAi: value)),
            ),
            if (_saving) const LinearProgressIndicator(),
            for (var kind = 0; kind < 3; kind++) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        s.blockedTags,
                        s.blockedArtists,
                        s.blockedArtworks,
                      ][kind],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saving ? null : () => _add(kind),
                    icon: const Icon(Icons.add),
                    label: Text(s.addBlock),
                  ),
                ],
              ),
              if ([
                    rules.tags.length,
                    rules.artists.length,
                    rules.artworks.length,
                  ][kind] ==
                  0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(s.noBlocks),
                ),
              for (final key
                  in (kind == 0
                      ? rules.tags
                      : kind == 1
                      ? rules.artists
                      : rules.artworks.keys))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    kind == 2
                        ? rules.artworks[key]!
                        : kind == 0
                        ? '#$key'
                        : '@$key',
                  ),
                  subtitle: kind == 2 ? Text(key) : null,
                  trailing: IconButton(
                    tooltip: s.unblock,
                    icon: const Icon(Icons.close),
                    onPressed: _saving
                        ? null
                        : () => _save(
                            (r) => switch (kind) {
                              0 => r.copyWith(tags: {...r.tags}..remove(key)),
                              1 => r.copyWith(
                                artists: {...r.artists}..remove(key),
                              ),
                              _ => r.copyWith(
                                artworks: {...r.artworks}..remove(key),
                              ),
                            },
                          ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
