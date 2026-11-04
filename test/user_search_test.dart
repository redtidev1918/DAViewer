import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/search/search_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Tokens implements AuthTokenProvider {
  @override
  Future<AuthTokens> validTokens({bool forceRefresh = false}) async =>
      AuthTokens(
        accessToken: 'test-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.utc(2100),
        scopes: const {OAuthScope.basic},
      );
}

void main() {
  test(
    'blank usernames return no results without accessing the runtime',
    () async {
      final container = ProviderContainer(retry: (_, _) => null);
      addTearDown(container.dispose);
      expect(await container.read(userSearchProvider('   ').future), isEmpty);
    },
  );

  test('user search looks up an unfollowed username outside friends', () async {
    // Request contract independently verified on 2026-11-04:
    // https://deviantart.readme.io/reference/user_whois
    // Stop before any response parsing: this is a routing regression, not a
    // fabricated external-response fixture.
    final requests = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          );
        },
      ),
    );
    addTearDown(() => dio.close(force: true));
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        runtimeProvider.overrideWithValue(
          AppRuntime(
            clientId: 'test-client',
            oauth: null,
            transport: OfficialApiClient(session: _Tokens(), dio: dio),
            transfers: BackgroundTransferManager(
              diagnostics: AppLogger.instance,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(userSearchProvider('  cyberxiandou-vore  ').future),
      throwsA(isA<DAKitException>()),
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(requests.single.uri.path, '/api/v1/oauth2/user/whois');
    expect(requests.single.data, {
      'usernames': ['cyberxiandou-vore'],
    });
  });
}
