import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/features/artwork/media_viewer.dart';
import 'package:daviewer/shared/route_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

// Platform seam follows video_player 2.14.0's published FakeVideoPlayerPlatform
// (test/video_player_test.dart), inspected 2026-10-14. No network protocol fixture.
class RecordingVideoPlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final calls = <String>[];
  // Per-player events for tests that distinguish simultaneous players.
  final playerEvents = <String>[];
  bool delayInitialization = false;
  Duration position = Duration.zero;

  void initializePlayer(int id) => streams[id]!.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      size: const Size(640, 360),
      duration: const Duration(minutes: 2),
    ),
  );

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = streams.length;
    streams[id] = StreamController<VideoEvent>();
    if (!delayInitialization) initializePlayer(id);
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    playerEvents.add('dispose:$playerId');
    await streams[playerId]!.close();
  }

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
    playerEvents.add('play:$playerId');
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
    playerEvents.add('pause:$playerId');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    calls.add('loop:$looping');
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration value) async {
    position = value;
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;
  @override
  Widget buildView(int playerId) => const SizedBox.expand();
}

void main() {
  late RecordingVideoPlatform platform;
  late VideoPlayerPlatform previousPlatform;
  final navigator = GlobalKey<NavigatorState>();

  setUp(() {
    previousPlatform = VideoPlayerPlatform.instance;
    platform = RecordingVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = previousPlatform);

  Future<void> mount(WidgetTester tester, {String url = 'video'}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [routeObserver],
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: MediaViewer(
                  media: [
                    MediaAsset(
                      id: 'video',
                      kind: MediaKind.video,
                      role: MediaRole.preview,
                      availability: MediaAvailability.available,
                      uri: Uri.parse('https://example.test/$url.mp4'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  /// Lets a player swap finish. `VideoPlayerController.dispose()` awaits the
  /// platform event-stream close, which needs real event-loop turns that
  /// FakeAsync never grants, so a bare `pump()` leaves the old controller
  /// undisposed forever. Verified in video_player 2.14.0 lib/video_player.dart
  /// `dispose()` -> `_eventSubscription.cancel()` -> platform `dispose()`.
  Future<void> settlePlayerSwap(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pause(WidgetTester tester) async {
    final explicitButton = find.byKey(const ValueKey('video-play-pause'));
    if (explicitButton.evaluate().isNotEmpty) {
      await tester.tap(explicitButton);
    } else {
      // Published Chewie renders pause through AnimatedPlayPause, not Icon.
      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.icon.runtimeType.toString() == 'AnimatedPlayPause',
            )
            .first,
      );
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<Chewie>(find.byType(Chewie, skipOffstage: false))
          .controller
          .videoPlayerController
          .value
          .isPlaying,
      isFalse,
    );
    platform.calls.clear();
  }

  Future<void> cover(WidgetTester tester) async {
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> uncover(WidgetTester tester) async {
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  }

  testWidgets('paused background taps never call play in any region', (
    tester,
  ) async {
    await mount(tester);
    await pause(tester);
    final rect = tester.getRect(find.byType(Chewie));
    for (final point in [
      rect.topLeft + const Offset(15, 15),
      rect.topRight + const Offset(-15, 15),
      rect.centerLeft + const Offset(15, 0),
      rect.centerRight + const Offset(-15, 0),
    ]) {
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 400));
      expect(platform.calls, isNot(contains('play')));
    }
    await cleanup(tester);
  });

  testWidgets('paused page return never calls play', (tester) async {
    await mount(tester);
    await pause(tester);
    await cover(tester);
    await uncover(tester);
    expect(platform.calls, isNot(contains('play')));
    await cleanup(tester);
  });

  testWidgets(
    'buffering and runtime error remain visible without leaking URLs',
    (tester) async {
      await mount(tester);
      expect(find.text('0:00 / 2:00'), findsOneWidget);
      platform.streams[0]!.add(
        VideoEvent(eventType: VideoEventType.bufferingStart),
      );
      // The stream event is delivered on a microtask and only marks the
      // ValueListenableBuilder dirty on the first pump; the spinner subtree
      // is built on the following frame.
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      platform.streams[0]!.addError(
        PlatformException(
          code: 'VideoError',
          message: 'private URL token=secret',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('secret'), findsNothing);
      expect(find.byKey(const ValueKey('video-play-pause')), findsNothing);
      expect(find.textContaining('视频加载失败'), findsOneWidget);
      await cleanup(tester);
    },
  );

  testWidgets('hidden center is background, not an invisible play button', (
    tester,
  ) async {
    await mount(tester);
    await pause(tester);
    final rect = tester.getRect(find.byType(Chewie));
    await tester.tapAt(rect.topLeft + const Offset(15, 15));
    await tester.pump();
    expect(find.byKey(const ValueKey('video-play-pause')), findsNothing);
    await tester.tapAt(rect.center);
    await tester.pump();
    expect(find.byKey(const ValueKey('video-play-pause')), findsOneWidget);
    expect(platform.calls, isNot(contains('play')));
    await cleanup(tester);
  });

  testWidgets('playing fullscreen and seeking do not pause or restart media', (
    tester,
  ) async {
    await mount(tester);
    platform.calls.clear();
    await tester.tap(find.byKey(const ValueKey('video-fullscreen')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('video-progress')),
      const Offset(75, 0),
    );
    await tester.pump();
    await uncover(tester);
    expect(platform.position, greaterThan(Duration.zero));
    expect(platform.calls, isNot(contains('pause')));
    expect(platform.calls, isNot(contains('play')));
    await cleanup(tester);
  });

  testWidgets(
    'autoplay loops; background taps preserve playing; button resumes',
    (tester) async {
      await mount(tester);
      expect(platform.calls, contains('play'));
      expect(platform.calls, contains('loop:true'));
      platform.calls.clear();
      final rect = tester.getRect(find.byType(Chewie));
      await tester.tapAt(rect.topLeft + const Offset(15, 15));
      await tester.pump();
      expect(platform.calls, isNot(contains('pause')));
      await tester.tapAt(rect.topLeft + const Offset(15, 15));
      await tester.pump();
      await pause(tester);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(platform.calls.where((call) => call == 'play'), hasLength(1));
      await cleanup(tester);
    },
  );

  testWidgets(
    'paused fullscreen entry exit and fullscreen pause preserve intent',
    (tester) async {
      await mount(tester);
      await pause(tester);
      await tester.tap(find.byKey(const ValueKey('video-fullscreen')));
      await tester.pumpAndSettle();
      expect(platform.calls, isNot(contains('play')));
      await tester.tap(find.byKey(const ValueKey('video-fullscreen')));
      await tester.pumpAndSettle();
      expect(platform.calls, isNot(contains('play')));
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('video-fullscreen')));
      await tester.pumpAndSettle();
      await pause(tester);
      await uncover(tester); // Android back gesture/button pops Chewie's route.
      expect(platform.calls, isNot(contains('play')));
      await cleanup(tester);
    },
  );

  testWidgets('seeking volume and speed preserve paused state', (tester) async {
    await mount(tester);
    await pause(tester);
    await tester.drag(
      find.byKey(const ValueKey('video-progress')),
      const Offset(75, 0),
    );
    await tester.pump();
    expect(platform.position, greaterThan(Duration.zero));
    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    await tester.tap(find.text('1.0x'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5x'));
    await tester.pumpAndSettle();
    expect(find.text('1.5x'), findsOneWidget);
    expect(platform.calls, isNot(contains('play')));
    await cleanup(tester);
  });

  testWidgets('route and app suspensions overlap without losing user intent', (
    tester,
  ) async {
    await mount(tester);
    await cover(tester);
    platform.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await uncover(tester);
    expect(platform.calls, isNot(contains('play')));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls, contains('play'));
    await pause(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls, isNot(contains('play')));
    await cleanup(tester);
  });

  testWidgets('initialization finishing on a covered route cannot autoplay', (
    tester,
  ) async {
    platform.delayInitialization = true;
    await mount(tester);
    await cover(tester);
    platform.initializePlayer(0);
    await tester.pump();
    await tester.pump();
    expect(platform.calls, isNot(contains('play')));
    await uncover(tester);
    expect(platform.calls, contains('play'));
    await cleanup(tester);
  });

  testWidgets(
    'sole ownership backgrounds media without any plugin replay path',
    (tester) async {
      await mount(tester);
      platform.calls.clear();
      // The app backgrounds while playing: DAViewer pauses (it owns the
      // lifecycle; video_player's private observer is disabled).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(platform.calls, contains('pause'));
      expect(platform.calls, isNot(contains('play')));
      // A system-interrupted video (user never paused) may resume.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.calls, contains('play'));
      // An explicit user pause outranks every automatic recovery afterwards.
      await pause(tester);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(platform.calls, isNot(contains('play')));
      await cleanup(tester);
    },
  );

  testWidgets(
    'switching the video url disposes the old player and resets intent',
    (tester) async {
      await mount(tester);
      await pause(tester);
      platform.playerEvents.clear();
      await mount(tester, url: 'video2');
      await settlePlayerSwap(tester);
      expect(platform.playerEvents, contains('dispose:0'));
      // The replacement video autoplays on its own player instance; the old
      // player never plays again and the previous pause intent is not carried
      // over.
      expect(platform.playerEvents, contains('play:1'));
      expect(platform.playerEvents, isNot(contains('play:0')));
      await cleanup(tester);
    },
  );
}
