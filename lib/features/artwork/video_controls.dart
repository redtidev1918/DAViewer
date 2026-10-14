import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';

/// Chewie's default paused hit area calls play even when
/// pauseOnBackgroundTap is false. Keep background and playback gestures separate.
class ArtworkVideoControls extends ConsumerStatefulWidget {
  const ArtworkVideoControls({super.key, required this.onTogglePlayback});

  final VoidCallback onTogglePlayback;

  @override
  ConsumerState<ArtworkVideoControls> createState() =>
      _ArtworkVideoControlsState();
}

class _ArtworkVideoControlsState extends ConsumerState<ArtworkVideoControls> {
  bool _visible = true;
  Timer? _hideTimer;
  double? _seekPosition;

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (ChewieController.of(context).videoPlayerController.value.isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _seekPosition == null) setState(() => _visible = false);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chewie = ChewieController.of(context);
    final controller = chewie.videoPlayerController;
    final s = strings(ref.watch(appLanguageProvider));
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, child) {
        final duration = value.duration.inMilliseconds.toDouble();
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              key: const ValueKey('video-background'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _visible = !_visible);
                _scheduleHide();
              },
            ),
            if (value.hasError)
              Center(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        s.videoLoadFailed,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            if (value.isBuffering && !value.hasError)
              const Positioned(
                top: 8,
                right: 8,
                child: IgnorePointer(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            if (_visible && !value.hasError)
              Center(
                child: IconButton.filled(
                  key: const ValueKey('video-play-pause'),
                  tooltip: value.isPlaying ? s.pause : s.videoPlay,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  iconSize: 36,
                  onPressed: () {
                    widget.onTogglePlayback();
                    _scheduleHide();
                  },
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
              ),
            if (_visible)
              Positioned(
                left: 8,
                top: 8,
                child: IgnorePointer(
                  child: Text(
                    '${_time(value.position)} / ${_time(value.duration)}',
                    style: const TextStyle(
                      color: Colors.white,
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
              ),
            if (_visible)
              Align(
                alignment: Alignment.bottomCenter,
                child: ColoredBox(
                  color: Colors.black54,
                  child: SafeArea(
                    top: false,
                    child: IconTheme(
                      data: const IconThemeData(color: Colors.white),
                      child: SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: value.volume == 0
                                  ? s.videoUnmute
                                  : s.videoMute,
                              onPressed: () {
                                controller.setVolume(value.volume == 0 ? 1 : 0);
                                _scheduleHide();
                              },
                              icon: Icon(
                                value.volume == 0
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                key: const ValueKey('video-progress'),
                                activeColor: Colors.red,
                                value:
                                    (_seekPosition ??
                                            value.position.inMilliseconds
                                                .toDouble())
                                        .clamp(0, duration > 0 ? duration : 1),
                                max: duration > 0 ? duration : 1,
                                onChangeStart: (_) => _hideTimer?.cancel(),
                                onChanged: duration <= 0 || value.hasError
                                    ? null
                                    : (position) {
                                        setState(
                                          () => _seekPosition = position,
                                        );
                                      },
                                onChangeEnd: (position) {
                                  // Seeking changes position only, never playback intent.
                                  controller.seekTo(
                                    Duration(milliseconds: position.round()),
                                  );
                                  setState(() => _seekPosition = null);
                                  _scheduleHide();
                                },
                              ),
                            ),
                            PopupMenuButton<double>(
                              tooltip: s.videoPlaybackSpeed,
                              initialValue: value.playbackSpeed,
                              onOpened: () => _hideTimer?.cancel(),
                              onCanceled: _scheduleHide,
                              onSelected: (speed) {
                                controller.setPlaybackSpeed(speed);
                                _scheduleHide();
                              },
                              itemBuilder: (_) => [
                                for (final speed in chewie.playbackSpeeds)
                                  PopupMenuItem(
                                    value: speed,
                                    child: Text('${speed}x'),
                                  ),
                              ],
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  '${value.playbackSpeed}x',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('video-fullscreen'),
                              tooltip: chewie.isFullScreen
                                  ? s.videoExitFullscreen
                                  : s.videoFullscreen,
                              onPressed: chewie.toggleFullScreen,
                              icon: Icon(
                                chewie.isFullScreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _time(Duration value) {
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    return value.inHours > 0
        ? '${value.inHours}:$minutes:$seconds'
        : '${value.inMinutes}:$seconds';
  }
}
