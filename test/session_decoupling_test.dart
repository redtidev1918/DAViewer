import 'dart:convert';
import 'dart:typed_data';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/auth/auth_controller.dart';
import 'package:daviewer/core/auth/auth_state.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/favourites/favourites_providers.dart';
import 'package:daviewer/features/home/home_providers.dart';
import 'package:daviewer/features/notifications/notifications_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingDioAdapter implements HttpClientAdapter {
  _RecordingDioAdapter(this.responses);

  final Map<String, Map<String, Object?>> responses;
  final List<String> requests = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    const prefix = '/api/v1/oauth2/';
    final rawPath = options.uri.path;
    final path = rawPath.startsWith(prefix)
        ? rawPath.substring(prefix.length)
        : rawPath;
    requests.add(path);
    final response = responses[path];
    if (response == null) {
      throw StateError('Unexpected request: $path');
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

final class _EmptyCallbackSource implements InitialCallbackUriSource {
  @override
  Future<Uri?> initialUri() async => null;

  @override
  Stream<Uri> get uris => Stream<Uri>.empty();
}

final class _MemoryTokenStore implements TokenStore {
  AuthTokens? tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens tokens) async {
    this.tokens = tokens;
  }

  @override
  Future<void> clear() async {
    tokens = null;
  }
}

final class _MemoryPendingAuthorizationStore
    implements PendingAuthorizationStore {
  PendingAuthorization? pending;

  @override
  Future<PendingAuthorization?> read() async => pending;

  @override
  Future<void> write(PendingAuthorization pending) async {
    this.pending = pending;
  }

  @override
  Future<void> clear() async {
    pending = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transfers = BackgroundTransferManager(diagnostics: AppLogger.instance);

  test(
    'web session transitions do not recreate or refetch favourites',
    () async {
      final dioAdapter = _RecordingDioAdapter(<String, Map<String, Object?>>{
        'user/whoami': <String, Object?>{
          'userid': 'user-1',
          'username': 'sample-user',
          'usericon': 'https://images.example.test/avatar.png',
          'type': 'regular',
          'verified': true,
        },
        'collections/all': <String, Object?>{
          'results': <Object?>[],
          'has_more': false,
          'next_offset': 0,
        },
      });
      final dio = Dio()..httpClientAdapter = dioAdapter;
      final tokenStore = _MemoryTokenStore()
        ..tokens = AuthTokens(
          accessToken: 'access-token',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          refreshToken: 'refresh-token',
          scopes: const <String>{OAuthScope.basic},
        );
      final oauth = DAKitOAuthClient(
        config: OAuthConfig(
          clientId: 'test-client',
          redirectUri: Uri.parse('dakit://oauth/callback'),
          scopes: const <String>{OAuthScope.basic},
        ),
        tokenStore: tokenStore,
        pendingStore: _MemoryPendingAuthorizationStore(),
        callbacks: _EmptyCallbackSource(),
      );
      final transport = OfficialApiClient(
        session: oauth.session,
        dio: dio,
        config: ApiConfig(userAgent: 'daviewer-test'),
      );
      final runtime = AppRuntime(
        clientId: 'test-client',
        oauth: oauth,
        transport: transport,
        transfers: transfers,
      );
      final container = ProviderContainer(
        overrides: <Override>[runtimeProvider.overrideWithValue(runtime)],
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).initialize();
      await container.read(authControllerProvider.notifier).accountLoad;
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.signedIn,
      );

      final subscription = container.listen(
        currentFavouritesProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        dioAdapter.requests.where((path) => path == 'collections/all'),
        hasLength(1),
      );
      final favourites = container.read(currentFavouritesProvider.notifier);
      final requestsBeforeWebChanges = dioAdapter.requests.length;

      final webStatus = container.read(webSessionStatusProvider.notifier);
      webStatus.markLocked();
      await Future<void>.delayed(Duration.zero);
      webStatus.markHealthy(serverUsername: 'sample-user');
      await Future<void>.delayed(Duration.zero);

      expect(
        identical(
          container.read(currentFavouritesProvider.notifier),
          favourites,
        ),
        isTrue,
      );
      expect(dioAdapter.requests.length, requestsBeforeWebChanges);
    },
  );

  test(
    'web session transitions do not refresh watched feed or messages',
    () async {
      final dioAdapter = _RecordingDioAdapter(<String, Map<String, Object?>>{
        'user/whoami': <String, Object?>{
          'userid': 'user-1',
          'username': 'sample-user',
          'usericon': 'https://images.example.test/avatar.png',
          'type': 'regular',
          'verified': true,
        },
        'browse/deviantsyouwatch': <String, Object?>{
          'results': <Object?>[],
          'has_more': false,
          'next_offset': 0,
        },
        'messages/feed': <String, Object?>{
          'results': <Object?>[],
          'has_more': false,
          'cursor': '',
        },
      });
      final dio = Dio()..httpClientAdapter = dioAdapter;
      final tokenStore = _MemoryTokenStore()
        ..tokens = AuthTokens(
          accessToken: 'access-token',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          refreshToken: 'refresh-token',
          scopes: const <String>{OAuthScope.basic},
        );
      final oauth = DAKitOAuthClient(
        config: OAuthConfig(
          clientId: 'test-client',
          redirectUri: Uri.parse('dakit://oauth/callback'),
          scopes: const <String>{OAuthScope.basic},
        ),
        tokenStore: tokenStore,
        pendingStore: _MemoryPendingAuthorizationStore(),
        callbacks: _EmptyCallbackSource(),
      );
      final transport = OfficialApiClient(
        session: oauth.session,
        dio: dio,
        config: ApiConfig(userAgent: 'daviewer-test'),
      );
      final runtime = AppRuntime(
        clientId: 'test-client',
        oauth: oauth,
        transport: transport,
        transfers: transfers,
      );
      final container = ProviderContainer(
        overrides: <Override>[runtimeProvider.overrideWithValue(runtime)],
      );
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).initialize();
      await container.read(authControllerProvider.notifier).accountLoad;
      final feedSubscription = container.listen(
        followingFeedProvider,
        (_, _) {},
      );
      final messagesSubscription = container.listen(
        notificationsProvider,
        (_, _) {},
      );
      addTearDown(feedSubscription.close);
      addTearDown(messagesSubscription.close);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        dioAdapter.requests.where((path) => path == 'browse/deviantsyouwatch'),
        hasLength(1),
      );
      expect(
        dioAdapter.requests.where((path) => path == 'messages/feed'),
        hasLength(1),
      );
      final followedFeed = container.read(followingFeedProvider.notifier);
      final requestsBeforeWebChanges = dioAdapter.requests.length;

      final webStatus = container.read(webSessionStatusProvider.notifier);
      webStatus.markLocked();
      await Future<void>.delayed(Duration.zero);
      webStatus.markHealthy(serverUsername: 'sample-user');
      await Future<void>.delayed(Duration.zero);

      expect(
        identical(container.read(followingFeedProvider.notifier), followedFeed),
        isTrue,
      );
      expect(dioAdapter.requests.length, requestsBeforeWebChanges);
    },
  );
}
