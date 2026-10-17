import 'package:dakit_core/dakit_core.dart';
import 'package:dakit_web/dakit_web.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content_rules.dart';

final platformAiMetadataProvider = Provider<PlatformAiMetadata>((ref) {
  final metadata = PlatformAiMetadata.instance;
  metadata.addListener(ref.notifyListeners);
  ref.onDispose(() => metadata.removeListener(ref.notifyListeners));
  return metadata;
});

/// App-side compatibility metadata until DAKit's Artwork exposes the platform
/// flag. Never infers AI from tags, descriptions or the NoAI training opt-out.
/// Wire evidence: test/fixtures/content_filter/README.md.
final class PlatformAiMetadata extends ChangeNotifier {
  static final instance = PlatformAiMetadata();
  final _flags = <String, bool>{};
  bool? forArtwork(Artwork artwork) =>
      _flags[artworkBlockKey(artwork.pageUri.toString())] ?? _flags[artwork.id];

  List<Map<String, Object>> snapshot(Iterable<Artwork> artworks) => [
    for (final artwork in artworks)
      if (forArtwork(artwork) case final bool flag)
        {
          'deviationId': artworkBlockKey(artwork.pageUri.toString()),
          'isAiGenerated': flag,
        },
  ];

  void observe(Object? data) {
    var changed = false;
    void visit(Object? node, int depth) {
      if (depth > 24) return;
      if (node is Map) {
        final id = node['deviationId'];
        final flag = node['isAiGenerated'];
        if ((id is int || id is String) && flag is bool) {
          final key = artworkBlockKey('$id');
          if (key.isNotEmpty) {
            changed = changed || _flags[key] != flag;
            _flags.remove(key);
            _flags[key] = flag;
          }
        }
        for (final value in node.values) {
          visit(value, depth + 1);
        }
      } else if (node is List) {
        for (final value in node) {
          visit(value, depth + 1);
        }
      }
    }

    if (data is String) {
      if (!data.contains('window.__INITIAL_STATE__ = JSON.parse(')) return;
      try {
        data = jsonParseAssignment(
          data,
          marker: 'window.__INITIAL_STATE__ = JSON.parse(',
          missingMessage: 'No artwork metadata',
        );
      } on FormatException {
        return;
      }
    }
    visit(data, 0);
    while (_flags.length > 10000) {
      _flags.remove(_flags.keys.first);
    }
    if (changed) notifyListeners();
  }
}

final class PlatformAiInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final host = response.requestOptions.uri.host;
    if (host == 'www.deviantart.com' || host == 'deviantart.com') {
      PlatformAiMetadata.instance.observe(response.data);
    }
    handler.next(response);
  }
}
