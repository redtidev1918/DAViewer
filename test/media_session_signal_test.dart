import 'package:daviewer/core/auth/media_session_signal.dart';
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Records the sources the media bridge forwards instead of running the whole
/// platform-dependent verdict chain (covered by web_session_status_test.dart).
final class _SignalRecorder {
  final List<String> sources = <String>[];

  void call(String source) => sources.add(source);
}

Widget _scope({required bool loggedIn, required _SignalRecorder recorder}) {
  return ProviderScope(
    retry: (_, _) => null,
    overrides: <Override>[
      webSessionSignalReporterProvider.overrideWithValue(recorder.call),
      webSessionControllerProvider.overrideWith(
        (ref) => WebSessionController(ref)
          ..state = WebSessionState(
            csrf: loggedIn ? 'token' : '',
            isLoggedIn: loggedIn,
            username: loggedIn ? 'artist' : '',
          ),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: Center(child: Text('probe'))),
    ),
  );
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.text('probe')),
      listen: false,
    );

void main() {
  group('MediaSessionSignal.isAuthRejection', () {
    test('recognizes cache-manager 401/403 exceptions', () {
      expect(
        MediaSessionSignal.isAuthRejection(HttpExceptionWithStatus(401, '')),
        isTrue,
      );
      expect(
        MediaSessionSignal.isAuthRejection(HttpExceptionWithStatus(403, '')),
        isTrue,
      );
    });

    test('recognizes status codes embedded in platform player errors', () {
      expect(
        MediaSessionSignal.isAuthRejection(
          StateError('VideoError: source responded with status 403 forbidden'),
        ),
        isTrue,
      );
      expect(
        MediaSessionSignal.isAuthRejection(
          Exception('HttpException: statusCode: 401, uri=https://x'),
        ),
        isTrue,
      );
    });

    test('ignores network failures, 404s and other errors', () {
      expect(
        MediaSessionSignal.isAuthRejection(
          HttpExceptionWithStatus(404, 'missing'),
        ),
        isFalse,
      );
      expect(
        MediaSessionSignal.isAuthRejection(
          Exception('Connection closed before full header was received'),
        ),
        isFalse,
      );
      expect(
        MediaSessionSignal.isAuthRejection(StateError('bad decode')),
        isFalse,
      );
    });
  });

  testWidgets('a media 403 while signed in forwards its source', (
    tester,
  ) async {
    final recorder = _SignalRecorder();
    await tester.pumpWidget(_scope(loggedIn: true, recorder: recorder));

    MediaSessionSignal.report(
      tester.element(find.text('probe')),
      HttpExceptionWithStatus(403, 'forbidden'),
      'media-image-403',
    );
    MediaSessionSignal.report(
      tester.element(find.text('probe')),
      StateError('player: status 401'),
      'media-video-401',
    );

    expect(recorder.sources, <String>['media-image-403', 'media-video-401']);
  });

  testWidgets('non-auth media errors never reach the verdict chain', (
    tester,
  ) async {
    final recorder = _SignalRecorder();
    await tester.pumpWidget(_scope(loggedIn: true, recorder: recorder));

    MediaSessionSignal.report(
      tester.element(find.text('probe')),
      HttpExceptionWithStatus(404, 'missing'),
      'media-image-404',
    );
    MediaSessionSignal.report(
      tester.element(find.text('probe')),
      Exception('Connection closed before full header was received'),
      'media-network-error',
    );

    expect(recorder.sources, isEmpty);
  });

  testWidgets('a signed-out device never forwards a media signal', (
    tester,
  ) async {
    final recorder = _SignalRecorder();
    await tester.pumpWidget(_scope(loggedIn: false, recorder: recorder));

    MediaSessionSignal.report(
      tester.element(find.text('probe')),
      HttpExceptionWithStatus(403, 'forbidden'),
      'media-image-403',
    );

    expect(recorder.sources, isEmpty);
  });

  testWidgets('a session already flagged for login suppresses the signal', (
    tester,
  ) async {
    final recorder = _SignalRecorder();
    await tester.pumpWidget(_scope(loggedIn: true, recorder: recorder));
    final container = _containerOf(tester);

    container.read(webSessionStatusProvider.notifier).state =
        const WebSessionStatus(state: WebSessionStatusState.anonymous);
    MediaSessionSignal.report(
      tester.element(find.text('probe')),
      HttpExceptionWithStatus(403, 'forbidden'),
      'media-image-403',
    );
    expect(recorder.sources, isEmpty);

    container.read(webSessionStatusProvider.notifier).markLocked();
    MediaSessionSignal.report(
      tester.element(find.text('probe')),
      HttpExceptionWithStatus(403, 'forbidden'),
      'media-image-403',
    );
    expect(recorder.sources, isEmpty);
  });

  testWidgets('a session inside the backoff cooldown suppresses the signal', (
    tester,
  ) async {
    final recorder = _SignalRecorder();
    await tester.pumpWidget(_scope(loggedIn: true, recorder: recorder));

    _containerOf(tester)
        .read(webSessionStatusProvider.notifier)
        .state = WebSessionStatus(
      cooldownUntil: DateTime.now().add(const Duration(minutes: 2)),
    );
    MediaSessionSignal.report(
      tester.element(find.text('probe')),
      HttpExceptionWithStatus(403, 'forbidden'),
      'media-image-403',
    );

    expect(recorder.sources, isEmpty);
  });

  testWidgets('the bridge requires a ProviderScope ancestor and fails silent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => MediaSessionSignal.report(
              context,
              HttpExceptionWithStatus(403, 'forbidden'),
              'media-image-403',
            ),
            child: const Text('trigger'),
          ),
        ),
      ),
    );

    // A widget rendered outside the app scope must not crash its errorWidget.
    expect(() => tester.tap(find.text('trigger')), returnsNormally);
  });
}
