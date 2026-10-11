import 'dart:convert';

import 'package:daviewer/core/auth/personalized_session_status.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _cursor(Object? value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

void main() {
  test('only the recorded generic group is a degradation signal', () {
    expect(
      rfyCursorSignalsGenericFallback(_cursor({'vespa_content_group': 2})),
      isTrue,
    );
    for (final value in [
      null,
      '',
      'bad-base64',
      _cursor({'offset': 24}),
      _cursor({'vespa_content_group': 1}),
      _cursor({'vespa_content_group': '2'}),
      _cursor([2]),
      'x' * 8193,
    ]) {
      expect(rfyCursorSignalsGenericFallback(value), isFalse);
    }
  });

  test('identity rechecks preserve degradation; a new login resets it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final identity = container.read(webSessionStatusProvider.notifier);
    identity.markHealthy(serverUsername: 'artist');
    final controller = container.read(
      personalizedSessionStatusProvider.notifier,
    );
    controller.observe(
      cookieHeader: 'fake=session',
      degraded: true,
      generation: identity.generation,
    );

    identity.state = const WebSessionStatus(
      state: WebSessionStatusState.healthy,
      serverUsername: 'artist',
    );
    expect(
      container.read(personalizedSessionStatusProvider).needsRecovery,
      isTrue,
    );
    identity.markHealthy(serverUsername: 'artist');
    expect(
      container.read(personalizedSessionStatusProvider).needsRecovery,
      isFalse,
    );
  });
}
