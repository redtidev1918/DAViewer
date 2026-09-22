import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_theme.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/route_observer.dart';
import '../../shared/widgets/full_screen_image_viewer.dart';
import 'artwork_navigation.dart';

/// Picks the single asset to display inline from an artwork's [media]:
/// a playable video first, then an animation, then the largest resampled
/// preview image (so the potentially huge original is never forced onto the
/// inline cache), falling back to any image. Gated assets (premium/paid,
/// blocked) are skipped when an accessible alternative exists, so paid content
/// still renders its accessible thumbnail instead of a broken image.
MediaAsset? selectDisplayAsset(List<MediaAsset> media) {
  if (media.isEmpty) return null;
  bool available(MediaAsset m) => m.availability == MediaAvailability.available;
  final video = media
      .where((m) => m.kind == MediaKind.video && available(m) && m.uri != null)
      .fold<MediaAsset?>(
        null,
        (best, candidate) =>
            best == null || _videoQuality(candidate) > _videoQuality(best)
            ? candidate
            : best,
      );
  if (video != null && video.uri != null) return video;
  final animation = media
      .where((m) => m.kind == MediaKind.animation && available(m))
      .firstOrNull;
  if (animation != null && animation.uri != null) return animation;
  final accessibleImage = media
      .where(
        (m) =>
            m.kind == MediaKind.image &&
            m.role == MediaRole.preview &&
            available(m),
      )
      .fold<MediaAsset?>(
        null,
        (best, m) =>
            best == null || (m.width ?? 0) > (best.width ?? 0) ? m : best,
      );
  if (accessibleImage != null) return accessibleImage;
  return media.where((m) => m.kind == MediaKind.image).firstOrNull;
}

int _videoQuality(MediaAsset asset) {
  final dimensions = (asset.height ?? 0) * (asset.width ?? 1);
  if (dimensions > 0) return dimensions;
  final quality = asset.filename == null
      ? null
      : RegExp(r'(\d{3,4})').firstMatch(asset.filename!)?.group(1);
  return int.tryParse(quality ?? '') ?? asset.byteLength ?? 0;
}

/// Renders an artwork's media: static images, animated GIFs, videos, and
/// multi-image pages (with a page counter and dot indicators).
final class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.media,
    this.additionalMedia = const <MediaAsset>[],
    this.heroTag,
    this.onPreviousArtwork,
    this.onNextArtwork,
    this.onDownloadImage,
  });

  final List<MediaAsset> media;
  final List<MediaAsset> additionalMedia;

  /// Hero tag for the first page's image, used to animate the grid → detail
  /// transition (matching [ArtworkCard]'s tag).
  final String? heroTag;
  final VoidCallback? onPreviousArtwork;
  final VoidCallback? onNextArtwork;
  final void Function(MediaAsset asset, int page)? onDownloadImage;

  @override
  State<MediaViewer> createState() => MediaViewerState();
}

final class MediaViewerState extends State<MediaViewer> {
  int _page = 0;
  final ArtworkEdgeSwipeTracker _edgeSwipe = ArtworkEdgeSwipeTracker();

  List<MediaAsset> get _pages => <MediaAsset>[
    ?selectDisplayAsset(widget.media),
    ...widget.additionalMedia,
  ];

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final fullScreenPages = pages.where(_canOpenFullScreen).toList();
    if (pages.isEmpty) {
      final s = strings(
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(appLanguageProvider),
      );
      return AspectRatio(
        aspectRatio: 1,
        child: _MediaMessage(icon: Icons.image_outlined, message: s.noImage),
      );
    }

    if (pages.length == 1) {
      return _pageWidget(
        pages.first,
        heroTag: widget.heroTag,
        fullScreenPages: fullScreenPages,
      );
    }

    return Column(
      children: <Widget>[
        Stack(
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    if (notification.dragDetails == null) {
                      _edgeSwipe.reset();
                    } else {
                      _edgeSwipe.start(
                        atFirst: _page == 0,
                        atLast: _page == pages.length - 1,
                      );
                    }
                  } else if (notification is OverscrollNotification) {
                    _edgeSwipe.add(notification.overscroll);
                  } else if (notification is ScrollEndNotification) {
                    final direction = _edgeSwipe.finish();
                    if (direction != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        switch (direction) {
                          case ArtworkSwipeDirection.previous:
                            widget.onPreviousArtwork?.call();
                          case ArtworkSwipeDirection.next:
                            widget.onNextArtwork?.call();
                        }
                      });
                    }
                  }
                  return false;
                },
                child: PageView.builder(
                  itemCount: pages.length,
                  onPageChanged: (index) {
                    _edgeSwipe.reset();
                    setState(() => _page = index);
                  },
                  itemBuilder: (context, index) => _pageWidget(
                    pages[index],
                    heroTag: index == 0 ? widget.heroTag : null,
                    fullScreenPages: fullScreenPages,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_page + 1} / ${pages.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            for (var i = 0; i < pages.length; i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _pageWidget(
    MediaAsset asset, {
    String? heroTag,
    required List<MediaAsset> fullScreenPages,
  }) {
    // Gated content (premium/paid, blocked, deleted): show a clear placeholder
    // instead of trying to load a URL that will 403 and render a broken image.
    if (asset.availability != MediaAvailability.available) {
      return _GatedPlaceholder(availability: asset.availability);
    }
    final url = asset.uri?.toString();
    if (url == null) {
      return const ColoredBox(
        color: AppTheme.placeholderColor,
        child: Icon(Icons.image, size: 48),
      );
    }
    final Widget child;
    if (asset.kind == MediaKind.video) {
      child = _VideoPlayer(url: url);
    } else if (asset.mimeType == 'image/gif') {
      // Animated GIFs render through Image.network so they actually animate.
      child = _AnimatedImage(
        url: url,
        fullScreenPages: fullScreenPages,
        initialPage: fullScreenPages.indexOf(asset),
        onPreviousArtwork: widget.onPreviousArtwork,
        onNextArtwork: widget.onNextArtwork,
        onDownloadImage: widget.onDownloadImage,
      );
    } else {
      child = _TappableImage(
        url: url,
        fullScreenPages: fullScreenPages,
        initialPage: fullScreenPages.indexOf(asset),
        onPreviousArtwork: widget.onPreviousArtwork,
        onNextArtwork: widget.onNextArtwork,
        onDownloadImage: widget.onDownloadImage,
      );
    }
    if (heroTag != null && asset.kind != MediaKind.video) {
      return Hero(tag: heroTag, child: child);
    }
    return child;
  }
}

bool _canOpenFullScreen(MediaAsset asset) =>
    asset.availability == MediaAvailability.available &&
    asset.uri != null &&
    asset.kind != MediaKind.video;

/// A centered icon + message used for empty/gated/error media states.
final class _MediaMessage extends StatelessWidget {
  const _MediaMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: AppTheme.placeholderColor,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 48, color: scheme.onSurfaceVariant),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A placeholder for content the user cannot access (premium/paid, blocked, or
/// deleted), showing the reason instead of a broken image.
final class _GatedPlaceholder extends StatelessWidget {
  const _GatedPlaceholder({required this.availability});

  final MediaAvailability availability;

  @override
  Widget build(BuildContext context) {
    final s = strings(
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(appLanguageProvider),
    );
    final label = switch (availability) {
      MediaAvailability.purchaseRequired => s.availabilityPurchaseRequired,
      MediaAvailability.restricted => s.availabilityRestricted,
      MediaAvailability.unavailable => s.availabilityUnavailable,
      MediaAvailability.loginRequired => s.availabilityLoginRequired,
      MediaAvailability.missing => s.availabilityMissing,
      MediaAvailability.available => '',
    };
    final icon = switch (availability) {
      MediaAvailability.purchaseRequired => Icons.lock_outline,
      MediaAvailability.restricted => Icons.visibility_off_outlined,
      MediaAvailability.missing => Icons.delete_outline,
      _ => Icons.block,
    };
    return AspectRatio(
      aspectRatio: 1,
      child: _MediaMessage(icon: icon, message: label),
    );
  }
}

final class _TappableImage extends StatelessWidget {
  const _TappableImage({
    required this.url,
    required this.fullScreenPages,
    required this.initialPage,
    this.onPreviousArtwork,
    this.onNextArtwork,
    this.onDownloadImage,
  });

  final String url;
  final List<MediaAsset> fullScreenPages;
  final int initialPage;
  final VoidCallback? onPreviousArtwork;
  final VoidCallback? onNextArtwork;
  final void Function(MediaAsset asset, int page)? onDownloadImage;

  @override
  Widget build(BuildContext context) {
    final providers = <ImageProvider<Object>>[
      for (final asset in fullScreenPages)
        CachedNetworkImageProvider(asset.uri.toString()),
    ];
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => FullScreenImageViewer(
            imageProvider: providers.first,
            additionalMedia: providers.skip(1).toList(),
            initialPage: initialPage,
            onPreviousArtwork: onPreviousArtwork,
            onNextArtwork: onNextArtwork,
            onImageLongPress: onDownloadImage == null
                ? null
                : (page) => onDownloadImage!(fullScreenPages[page], page),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          width: double.infinity,
          memCacheWidth: 1080,
          // Progressive loading: show a tiny (blurred) version of the same
          // image instantly, then cross-fade to the full-resolution decode.
          placeholder: (context, url) => AspectRatio(
            aspectRatio: 1,
            child: CachedNetworkImage(
              imageUrl: url,
              memCacheWidth: 40,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  const ColoredBox(color: AppTheme.placeholderColor),
              errorWidget: (context, url, error) =>
                  const ColoredBox(color: AppTheme.placeholderColor),
            ),
          ),
          errorWidget: (context, url, error) => AspectRatio(
            aspectRatio: 1,
            child: _MediaMessage(
              icon: Icons.broken_image_outlined,
              message: strings(
                ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(appLanguageProvider),
              ).imageLoadFailed,
            ),
          ),
        ),
      ),
    );
  }
}

final class _AnimatedImage extends StatelessWidget {
  const _AnimatedImage({
    required this.url,
    required this.fullScreenPages,
    required this.initialPage,
    this.onPreviousArtwork,
    this.onNextArtwork,
    this.onDownloadImage,
  });

  final String url;
  final List<MediaAsset> fullScreenPages;
  final int initialPage;
  final VoidCallback? onPreviousArtwork;
  final VoidCallback? onNextArtwork;
  final void Function(MediaAsset asset, int page)? onDownloadImage;

  @override
  Widget build(BuildContext context) {
    final providers = <ImageProvider<Object>>[
      for (final asset in fullScreenPages)
        CachedNetworkImageProvider(asset.uri.toString()),
    ];
    final decodeWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(480, 2048)
            .toInt();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => FullScreenImageViewer(
            imageProvider: providers.first,
            additionalMedia: providers.skip(1).toList(),
            initialPage: initialPage,
            onPreviousArtwork: onPreviousArtwork,
            onNextArtwork: onNextArtwork,
            onImageLongPress: onDownloadImage == null
                ? null
                : (page) => onDownloadImage!(fullScreenPages[page], page),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          width: double.infinity,
          memCacheWidth: decodeWidth,
          fadeInDuration: const Duration(milliseconds: 180),
          progressIndicatorBuilder: (context, url, progress) => AspectRatio(
            aspectRatio: 1,
            child: ColoredBox(
              color: AppTheme.placeholderColor,
              child: Center(
                child: CircularProgressIndicator(value: progress.progress),
              ),
            ),
          ),
          errorWidget: (context, url, error) => AspectRatio(
            aspectRatio: 1,
            child: _MediaMessage(
              icon: Icons.broken_image_outlined,
              message: strings(
                ProviderScope.containerOf(
                  context,
                  listen: false,
                ).read(appLanguageProvider),
              ).imageLoadFailed,
            ),
          ),
        ),
      ),
    );
  }
}

final class _VideoPlayer extends StatefulWidget {
  const _VideoPlayer({required this.url});

  final String url;

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

final class _VideoPlayerState extends State<_VideoPlayer>
    with WidgetsBindingObserver, RouteAware {
  VideoPlayerController? _controller;
  ChewieController? _chewie;
  Object? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _VideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  Future<void> _initialize() async {
    final generation = ++_loadGeneration;
    final oldChewie = _chewie;
    final oldController = _controller;
    _chewie = null;
    _controller = null;
    oldChewie?.dispose();
    await oldController?.dispose();
    if (!mounted || generation != _loadGeneration) return;
    setState(() => _error = null);

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted ||
          generation != _loadGeneration ||
          _controller != controller) {
        await controller.dispose();
        return;
      }
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: controller,
          // Videos play automatically and loop, matching the inline,
          // social-feed style of the rest of the media viewer.
          autoPlay: true,
          looping: true,
          allowFullScreen: true,
          allowMuting: true,
          allowPlaybackSpeedChanging: true,
          showControlsOnInitialize: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: Colors.red,
            handleColor: Colors.red,
            bufferedColor: Colors.red.shade200,
          ),
        );
      });
    } on Object catch (error) {
      if (!mounted ||
          generation != _loadGeneration ||
          _controller != controller) {
        await controller.dispose();
        return;
      }
      _controller = null;
      await controller.dispose();
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  @override
  void didPushNext() => _controller?.pause();

  @override
  void didPopNext() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      controller.play();
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _chewie?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final s = strings(
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(appLanguageProvider),
      );
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.videocam_off, color: Colors.white, size: 42),
                  const SizedBox(height: 8),
                  Text(
                    s.videoLoadFailed,
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextButton.icon(
                    onPressed: _initialize,
                    icon: const Icon(Icons.refresh),
                    label: Text(s.retry),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final controller = _controller;
    final chewie = _chewie;
    if (controller == null ||
        chewie == null ||
        !controller.value.isInitialized) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : 16 / 9,
      child: Chewie(controller: chewie),
    );
  }
}
