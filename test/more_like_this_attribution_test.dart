import 'dart:typed_data';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/artwork/artwork_detail_providers.dart';
import 'package:daviewer/features/artwork/more_like_this_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Failure attribution for "More Like This", from the 2026-10-14 Android
/// incident: RFY and numeric-id details failed with a web-session 403, and the
/// log reported `MoreLikeThisFailure(website: 403, official: 403)` even though
/// no official request was ever sent.
///
/// Resolving the OAuth UUID is a *website* step for numeric ids
/// (`dadeviation/init`), so its failure must stay attributed to the website
/// source. These tests pin that contract on the real provider body.
///
/// FileDownloaderBackend exposes a single-subscription `updates` stream, so all
/// tests in this file share one transfer manager.
final _sharedTransfers = BackgroundTransferManager(
  diagnostics: AppLogger.instance,
);

final class _Tokens implements AuthTokenProvider {
  @override
  Future<AuthTokens> validTokens({bool forceRefresh = false}) async =>
      AuthTokens(
        accessToken: 'test-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
}

/// Fails every official request, so a genuine official failure can be
/// distinguished from a UUID-resolution failure.
final class _AlwaysFailingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'official endpoint unreachable',
    );
  }
}

/// A web-session 403 exactly as the incident produced it.
DioException _webSessionForbidden() => DioException(
  requestOptions: RequestOptions(path: '/_puppy/dadeviation/init'),
  response: Response<void>(
    requestOptions: RequestOptions(path: '/_puppy/dadeviation/init'),
    statusCode: 403,
  ),
  type: DioExceptionType.badResponse,
);

/// The `pageUri` deliberately has no trailing numeric id, so the provider's
/// website-related lookup is skipped and the test isolates UUID resolution.
Artwork _artwork(String id) => Artwork(
  id: id,
  title: 'Seed',
  author: const UserProfile(id: 'artist', username: 'artist'),
  pageUri: Uri.parse('https://www.deviantart.com/artist/art/seed'),
  media: <MediaAsset>[
    MediaAsset(
      id: '$id:preview',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      uri: Uri.parse('https://images.example.test/preview.jpg'),
    ),
  ],
);

const _uuid = 'A47E9A8B-7A7F-3C7C-5367-DBC635E21816';

ProviderContainer _container({
  required Object? uuidError,
  String? uuid = _uuid,
  HttpClientAdapter? adapter,
}) {
  final dio = Dio()..httpClientAdapter = adapter ?? _AlwaysFailingAdapter();
  final container = ProviderContainer(
    // Riverpod 3 retries a failed provider with backoff by default, which would
    // keep these deliberately-failing providers pending until the test times out.
    retry: (_, _) => null,
    overrides: <Override>[
      runtimeProvider.overrideWithValue(
        AppRuntime(
          clientId: 'test-client',
          oauth: null,
          transport: OfficialApiClient(session: _Tokens(), dio: dio),
          transfers: _sharedTransfers,
        ),
      ),
      artworkDetailProvider(_uuid).overrideWith((ref) async => _artwork(_uuid)),
      artworkUuidProvider(_uuid).overrideWith((ref) async {
        if (uuidError != null) throw uuidError;
        return uuid!;
      }),
    ],
  );
  addTearDown(container.dispose);
  // Both providers are autoDispose: a bare `read(provider.future)` leaves them
  // unlistened, so they are disposed mid-load and the real error is replaced by
  // a disposal StateError. Keep the root provider subscribed instead.
  final keepAlive = container.listen(moreLikeThisProvider(_uuid), (_, _) {});
  addTearDown(keepAlive.close);
  return container;
}

void main() {
  test(
    'uuid resolution failure is a website failure and never an official one',
    () async {
      final container = _container(uuidError: _webSessionForbidden());

      final failure = await container
          .read(moreLikeThisProvider(_uuid).future)
          .then<Object?>((_) => null)
          .onError<Object>((error, _) => error);

      expect(failure, isA<MoreLikeThisFailure>());
      final typed = failure! as MoreLikeThisFailure;
      // The core regression: no official request was attempted, so the failure
      // must not claim the official API failed.
      expect(
        typed.officialError,
        isNull,
        reason: 'the official request is never sent without a UUID',
      );
      expect(typed.websiteError, isA<DioException>());
      expect((typed.websiteError! as DioException).response?.statusCode, 403);
      // The user-visible classification is unchanged by the reattribution:
      // a raw website 403 has always mapped to the service kind.
      expect(typed.kind, MoreLikeThisFailureKind.service);
    },
  );

  test('a genuine official failure keeps its own attribution', () async {
    final container = _container(uuidError: null);

    final failure = await container
        .read(moreLikeThisProvider(_uuid).future)
        .then<Object?>((_) => null)
        .onError<Object>((error, _) => error);

    expect(failure, isA<MoreLikeThisFailure>());
    final typed = failure! as MoreLikeThisFailure;
    expect(
      typed.officialError,
      isNotNull,
      reason: 'the official endpoint was reached and failed',
    );
    expect(
      typed.websiteError,
      isNull,
      reason: 'the website source was skipped, not failing',
    );
  });
}
