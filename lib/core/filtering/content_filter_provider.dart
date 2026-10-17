import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dakit_core/dakit_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/artwork/artwork_store.dart';

import '../storage/storage_queue.dart';
import 'content_rules.dart';
import 'platform_ai_metadata.dart';

final contentRulesStoreProvider = Provider((ref) => ContentRulesStore());
final initialContentRulesProvider = Provider<ContentRules?>(
  (ref) => ContentRules(),
);
final contentRulesProvider =
    AsyncNotifierProvider<ContentRulesController, ContentRules>(
      ContentRulesController.new,
    );

final class ContentRulesStore {
  ContentRulesStore({this.directory});
  final Directory? directory;
  Future<File> _file() async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}content_blocks.json');
  }

  Future<ContentRules> load() async {
    final file = await _file();
    if (!await file.exists()) return ContentRules();
    return ContentRules.fromJson(jsonDecode(await file.readAsString()));
  }

  Future<void> save(ContentRules rules) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(rules.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}

final class ContentRulesController extends AsyncNotifier<ContentRules> {
  final _queue = StorageQueue();
  @override
  FutureOr<ContentRules> build() {
    final initial = ref.watch(initialContentRulesProvider);
    if (initial != null) return initial;
    return ref.read(contentRulesStoreProvider).load();
  }

  Future<void> changeRules(ContentRules Function(ContentRules) change) =>
      _queue.run(() async {
        final current = await future;
        if (!ref.mounted) return;
        final next = change(current);
        await ref.read(contentRulesStoreProvider).save(next);
        if (ref.mounted) state = AsyncData(next);
      });
  Future<void> blockArtwork(Artwork artwork) => changeRules((rules) {
    final key = artworkBlockKey(artwork.pageUri.toString());
    final id = key.isEmpty ? artworkBlockKey(artwork.id) : key;
    if (id.isEmpty) throw const FormatException('Invalid artwork ID');
    return rules.copyWith(artworks: {...rules.artworks, id: artwork.title});
  });
  Future<void> blockArtist(String name) => changeRules(
    (r) => r.copyWith(artists: {...r.artists, normalizeArtist(name)}),
  );
}

/// Filters presentation only; original items/cursors remain intact for paging.
List<Artwork> visibleArtworks(WidgetRef ref, Iterable<Artwork> items) {
  final rules = ref.watch(contentRulesProvider).value;
  final metadata = ref.watch(platformAiMetadataProvider);
  final cached = ref.watch(artworkStoreProvider);
  if (rules == null) return const [];
  return items
      .map((artwork) => cached[artwork.id] ?? artwork)
      .where((a) => !rules.blocks(a, isAi: metadata.forArtwork(a)))
      .toList(growable: false);
}
