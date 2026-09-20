import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/diagnostics/error_text.dart';
import '../../core/history/visit_history_store.dart';
import '../../core/auth/web_session_refresher.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/runtime/runtime_provider.dart';
import '../../core/sharing/app_share.dart';
import '../../shared/widgets/app_error_state.dart';
import '../../shared/widgets/skeleton.dart';
import '../downloads/download_helpers.dart';
import '../history/history_providers.dart';
import 'artwork_detail_providers.dart';
import 'artwork_detail_sections.dart';
import 'artwork_navigation.dart';
import 'artwork_store.dart';
import 'download_section.dart';
import 'download_planner.dart';
import 'download_reason.dart';
import 'favourite_actions.dart';
import 'media_viewer.dart';
import 'collection_sections.dart';
import 'more_from_artist.dart';
import 'more_like_this.dart';
import 'similar_artists.dart';

final class ArtworkDetailScreen extends ConsumerStatefulWidget {
  const ArtworkDetailScreen({
    required this.artworkId,
    this.username,
    this.browseSession,
    super.key,
  });

  final String artworkId;

  /// The artwork's author when opened from a pasted link, so the numeric-id
  /// resolver can find the deviation without a cached feed item.
  final String? username;
  final ArtworkBrowseSession? browseSession;

  @override
  ConsumerState<ArtworkDetailScreen> createState() =>
      _ArtworkDetailScreenState();
}

final class _ArtworkDetailScreenState extends ConsumerState<ArtworkDetailScreen>
    with SingleTickerProviderStateMixin {
  StreamSubscription<TransferSnapshot>? _subscription;
  TransferSnapshot? _transfer;
  bool _downloading = false;
  bool _favourite = false;
  bool _favBusy = false;
  bool _navigatingArtwork = false;
  String? _recordedVisitId;
  String? _reportedTransferFailure;

  late final AnimationController _heartController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _heartScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.4,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.4,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeInBack)),
      weight: 50,
    ),
  ]).animate(_heartController);

  @override
  void initState() {
    super.initState();
    // When opened from a pasted link the author comes from the URL (there is
    // no cached feed item); surface it for the numeric-id resolver.
    ref.read(linkUsernameProvider.notifier).state = widget.username;
    // Warm the image cache for the adjacent artworks so swiping to them is
    // instant instead of flashing a placeholder while their media loads.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchNeighbors());
  }

  void _prefetchNeighbors() {
    final session = widget.browseSession;
    if (session == null || !mounted) return;
    final store = ref.read(artworkStoreProvider);
    for (final id in <String?>[
      session.previousOf(widget.artworkId),
      session.nextOf(widget.artworkId),
    ]) {
      if (id == null) continue;
      final neighbor = store[id];
      if (neighbor == null) continue;
      // Prefetch only a static image; feeding a video URL to the image codec
      // would fail (and waste a download). Video neighbours load their own
      // poster when opened.
      final uri = _displayImageUri(neighbor.media);
      if (uri == null) continue;
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(uri.toString(), maxWidth: 1080),
          context,
        ),
      );
    }
  }

  /// The largest available preview image in [media], or null when the artwork
  /// is video/animation-only (there is no static image to prefetch).
  Uri? _displayImageUri(List<MediaAsset> media) {
    MediaAsset? best;
    for (final asset in media) {
      if (asset.kind != MediaKind.image ||
          asset.availability != MediaAvailability.available ||
          asset.uri == null) {
        continue;
      }
      if (best == null || (asset.width ?? 0) > (best.width ?? 0)) best = asset;
    }
    return best?.uri;
  }

  @override
  void dispose() {
    _heartController.dispose();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ArtworkDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkId == widget.artworkId) return;
    _recordedVisitId = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _transfer = null;
    _downloading = false;
    _favourite = false;
    _favBusy = false;
    _navigatingArtwork = false;
    _reportedTransferFailure = null;
  }

  Future<void> _recordVisit(Artwork artwork) async {
    await VisitHistoryStore.record(artwork);
    if (mounted) ref.invalidate(visitHistoryProvider);
  }

  Future<void> _toggleFavourite() async {
    if (_favBusy) return;
    setState(() => _favBusy = true);
    try {
      final isFavourite = await setArtworkFavourite(
        ref,
        widget.artworkId,
        !_favourite,
      );
      if (!mounted) return;
      setState(() => _favourite = isFavourite);
      _heartController.forward(from: 0);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _favBusy = false);
    }
  }

  void _openLink(String? url) {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }

  Future<void> _download(
    MediaAsset original, {
    String? id,
    bool track = true,
    List<MediaAsset> pages = const <MediaAsset>[],
  }) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final manager = ref.read(runtimeProvider).transfers;
      final transferId = id ?? 'artwork-${widget.artworkId}-original';
      await manager.initialize();
      final existing = (await manager.records())
          .where((record) => record.id == transferId)
          .firstOrNull;
      if (existing != null) {
        if (const <TransferState>{
          TransferState.failed,
          TransferState.notFound,
          TransferState.cancelled,
        }.contains(existing.state)) {
          await manager.remove(transferId);
        } else {
          if (!mounted) return;
          _showTransferMessage(existing);
          if (track) await _trackTransfer(manager, existing);
          return;
        }
      }
      final snapshot = await manager.enqueue(
        TransferRequest(
          id: transferId,
          asset: original,
          filename: original.filename,
        ),
      );
      if (!mounted) return;
      _showTransferMessage(snapshot);
      // 多图作品：主图之后把每一附加页的原图也入队（一键下载全部页）
      if (pages.isNotEmpty) {
        final existingIds = (await manager.records())
            .map((record) => record.id)
            .toSet();
        for (var index = 0; index < pages.length; index++) {
          final page = pages[index];
          if (!page.canTransfer) continue;
          final pageId = imageTransferId(
            widget.artworkId,
            page.id.isEmpty ? 'page:${index + 1}' : page.id,
          );
          if (existingIds.contains(pageId)) continue;
          existingIds.add(pageId);
          await manager.enqueue(
            TransferRequest(id: pageId, asset: page, filename: page.filename),
          );
        }
      }
      if (!track) return;
      await _trackTransfer(manager, snapshot);
    } on Object catch (error) {
      if (mounted) {
        final s = strings(ref.read(appLanguageProvider));
        final reason = immediateDownloadFailureReason(s, error);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.downloadFailed(reason))));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _confirmAndDownloadImage(MediaAsset asset, int page) async {
    final confirmed = await confirmImageDownload(
      context,
      strings: strings(ref.read(appLanguageProvider)),
    );
    if (!confirmed || !mounted) return;
    await _download(
      asset,
      id: imageTransferId(
        widget.artworkId,
        asset.id.isEmpty ? 'page:${page + 1}' : asset.id,
      ),
      track: false,
    );
  }

  void _showTransferMessage(TransferSnapshot snapshot) {
    final s = strings(ref.read(appLanguageProvider));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(transferStatusMessage(s, snapshot))));
  }

  Future<void> _trackTransfer(
    TransferManager manager,
    TransferSnapshot snapshot,
  ) async {
    setState(() => _transfer = snapshot);
    _reportTransferFailure(snapshot);
    final previous = _subscription;
    _subscription = null;
    await previous?.cancel();
    if (!mounted) return;
    final transferId = snapshot.id;
    _subscription = manager.updates
        .where((update) => update.id == transferId)
        .listen((update) {
          if (!mounted) return;
          setState(() => _transfer = update);
          _reportTransferFailure(update);
        });
  }

  void _reportTransferFailure(TransferSnapshot snapshot) {
    if (!mounted ||
        (snapshot.state != TransferState.failed &&
            snapshot.state != TransferState.notFound)) {
      return;
    }
    final signature =
        '${snapshot.id}:${snapshot.state.name}:${snapshot.failureCode}:${snapshot.failureMessage}';
    if (_reportedTransferFailure == signature) return;
    _reportedTransferFailure = signature;
    final s = strings(ref.read(appLanguageProvider));
    final reason = transferFailureReason(s, snapshot);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.downloadFailed(reason))));
  }

  Future<void> _retryDownload(MediaAsset asset) async {
    final previous = _transfer;
    if (previous != null && previous.isFinal) {
      try {
        await ref.read(runtimeProvider).transfers.remove(previous.id);
      } on Object {
        // A failed record without a usable local file must not block retrying.
      }
    }
    if (!mounted) return;
    setState(() {
      _transfer = null;
      _reportedTransferFailure = null;
    });
    await _download(asset);
  }

  Future<void> _retryDownloadAvailability() async {
    try {
      if (isNumericDeviationId(widget.artworkId)) {
        await ref.read(webSessionRefresherProvider).refresh();
      }
    } on Object {
      // The provider below retains a failed refresh as a retryable lookup
      // state, so the detail page still stays usable.
    }
    if (!mounted) return;
    ref.invalidate(deviationInitProvider(widget.artworkId));
    ref.invalidate(artworkUuidProvider(widget.artworkId));
    ref.invalidate(originalFileProvider(widget.artworkId));
  }

  Future<void> _pause() async {
    final transfer = _transfer;
    if (transfer == null) return;
    await ref.read(runtimeProvider).transfers.pause(transfer.id);
  }

  Future<void> _resume() async {
    final transfer = _transfer;
    if (transfer == null) return;
    await ref.read(runtimeProvider).transfers.resume(transfer.id);
  }

  Future<void> _cancel() async {
    final transfer = _transfer;
    if (transfer == null) return;
    await ref.read(runtimeProvider).transfers.cancel(transfer.id);
  }

  void _navigateArtwork(int offset) {
    if (_navigatingArtwork) return;
    final session = widget.browseSession;
    final target = session?.target(
      widget.artworkId,
      offset < 0
          ? ArtworkNavigationDirection.previous
          : ArtworkNavigationDirection.next,
    );
    if (target == null) return;
    _navigatingArtwork = true;
    context.pushReplacement(
      '/artwork/${target.artworkId}',
      extra: target.routeContext,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(ref.watch(appLanguageProvider));
    final artwork = ref.watch(artworkDetailProvider(widget.artworkId));
    final original = ref.watch(originalFileProvider(widget.artworkId));
    final description = ref.watch(artworkDescriptionProvider(widget.artworkId));
    final descriptionHtml = ref.watch(
      artworkDescriptionHtmlProvider(widget.artworkId),
    );
    final journalHtml = ref.watch(journalHtmlProvider(widget.artworkId));
    final additionalMedia = ref.watch(
      additionalMediaProvider(widget.artworkId),
    );
    final additionalOriginals = ref.watch(
      additionalOriginalsProvider(widget.artworkId),
    );
    final tags = ref.watch(artworkTagsProvider(widget.artworkId));
    final dates = ref.watch(artworkDatesProvider(widget.artworkId));
    final transfer = _transfer;
    final previousArtwork = widget.browseSession?.previousOf(widget.artworkId);
    final nextArtwork = widget.browseSession?.nextOf(widget.artworkId);

    // Reflect the real favourite state once it loads (the heart must show as
    // filled when re-opening an already-favourited artwork).
    ref.listen<AsyncValue<bool>>(favouriteStatusProvider(widget.artworkId), (
      previous,
      next,
    ) {
      final value = next.valueOrNull;
      if (value != null && mounted) {
        setState(() => _favourite = value);
      }
    });

    // Record once after the artwork actually resolves, so failed loads and
    // transient rebuilds do not pollute local history.
    final loadedArtwork = artwork.valueOrNull;
    if (loadedArtwork != null && _recordedVisitId != widget.artworkId) {
      _recordedVisitId = widget.artworkId;
      unawaited(_recordVisit(loadedArtwork));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(artwork.valueOrNull?.title ?? s.artworkDetail),
        actions: <Widget>[
          IconButton(
            tooltip: s.previousArtwork,
            visualDensity: VisualDensity.compact,
            onPressed: previousArtwork == null
                ? null
                : () => _navigateArtwork(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: s.nextArtwork,
            visualDensity: VisualDensity.compact,
            onPressed: nextArtwork == null ? null : () => _navigateArtwork(1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: s.share,
            onPressed: artwork.valueOrNull == null
                ? null
                : () => shareDeviantArtLink(
                    context,
                    uri: artwork.valueOrNull!.pageUri,
                    title: artwork.valueOrNull!.title,
                    strings: s,
                  ),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: _favourite ? s.unfavourite : s.favourite,
            onPressed: _toggleFavourite,
            icon: ScaleTransition(
              scale: _heartScale,
              child: Icon(
                _favourite ? Icons.favorite : Icons.favorite_border,
                color: _favourite ? Colors.red : null,
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: artwork.when(
          loading: () => const SkeletonDetail(key: ValueKey('skeleton-art')),
          error: (error, stackTrace) => AppErrorState(
            key: const ValueKey('error-art'),
            message: friendlyErrorMessage(error),
            onRetry: () =>
                ref.invalidate(artworkDetailProvider(widget.artworkId)),
          ),
          data: (artwork) => KeyedSubtree(
            key: const ValueKey('content'),
            child: _buildBody(
              artwork,
              original,
              transfer,
              description: description.valueOrNull,
              descriptionHtml: descriptionHtml.valueOrNull,
              journalHtml: journalHtml.valueOrNull,
              additionalMedia:
                  additionalMedia.valueOrNull ?? const <MediaAsset>[],
              additionalOriginals:
                  additionalOriginals.valueOrNull ?? const <MediaAsset>[],
              tags: tags.valueOrNull ?? const <String>[],
              dates: dates.valueOrNull ?? const ArtworkDates(),
              hasPreviousArtwork: previousArtwork != null,
              hasNextArtwork: nextArtwork != null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    Artwork artwork,
    AsyncValue<OriginalFileResolution> originalResolution,
    TransferSnapshot? transfer, {
    String? description,
    String? descriptionHtml,
    String? journalHtml,
    List<MediaAsset> additionalMedia = const <MediaAsset>[],
    List<MediaAsset> additionalOriginals = const <MediaAsset>[],
    List<String> tags = const <String>[],
    ArtworkDates dates = const ArtworkDates(),
    bool hasPreviousArtwork = false,
    bool hasNextArtwork = false,
  }) {
    final s = strings(ref.read(appLanguageProvider));
    final media = artwork.media;
    // Journals/literature are rendered as text (with any embedded thumbs shown
    // above), never as an image with a bogus "original deleted" download row.
    final isJournal = artwork.pageUri.path.contains('/journal/');
    // The detail screen is a thin composition of self-contained sections. To
    // add another related-content block (e.g. Suggested Deviants / Collections),
    // drop a new widget below; each section owns its provider, its loading /
    // error / empty handling, and hides itself when it has nothing to show.
    return ArtworkSwipeRegion(
      onPrevious: hasPreviousArtwork ? () => _navigateArtwork(-1) : null,
      onNext: hasNextArtwork ? () => _navigateArtwork(1) : null,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (media.isNotEmpty) ...[
            MediaViewer(
              media: media,
              additionalMedia: additionalMedia,
              heroTag: 'artwork-${artwork.id}',
              onPreviousArtwork: hasPreviousArtwork
                  ? () => _navigateArtwork(-1)
                  : null,
              onNextArtwork: hasNextArtwork ? () => _navigateArtwork(1) : null,
              onDownloadImage: (asset, page) =>
                  unawaited(_confirmAndDownloadImage(asset, page)),
            ),
            const SizedBox(height: 16),
          ],
          ArtworkHeader(artwork: artwork, s: s),
          ArtworkDateSection(
            publishedAt: dates.publishedAt ?? artwork.publishedAt,
            updatedAt: dates.updatedAt,
            s: s,
          ),
          const Divider(),
          ArtworkDescriptionSection(
            isJournal: isJournal,
            s: s,
            journalHtml: journalHtml,
            descriptionHtml: descriptionHtml,
            description: description,
            onOpenLink: _openLink,
          ),
          if (tags.isNotEmpty) ArtworkTagsSection(tags: tags),
          if (!isJournal && media.isNotEmpty) ...[
            const SizedBox(height: 8),
            originalResolution.when(
              loading: () => Row(
                children: <Widget>[
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(s.checkingDownloadAvailability),
                ],
              ),
              error: (error, stackTrace) => Row(
                children: <Widget>[
                  Expanded(child: Text(s.downloadAvailabilityCheckFailed)),
                  TextButton(
                    onPressed: () => unawaited(_retryDownloadAvailability()),
                    child: Text(s.retry),
                  ),
                ],
              ),
              data: (resolution) => _buildDownloadSection(
                s,
                media,
                resolution,
                transfer,
                additionalOriginals,
              ),
            ),
          ],
          const Divider(),
          MoreFromArtistSection(artworkId: widget.artworkId),
          MoreLikeThisSection(artworkId: widget.artworkId),
          SimilarArtistsSection(artworkId: widget.artworkId),
          FeaturedInCollectionsSection(artworkId: widget.artworkId),
          SuggestedCollectionsSection(artworkId: widget.artworkId),
        ],
      ),
    );
  }

  Widget _buildDownloadSection(
    AppStrings s,
    List<MediaAsset> media,
    OriginalFileResolution resolution,
    TransferSnapshot? transfer,
    List<MediaAsset> additionalOriginals,
  ) {
    final plan = planDownload(original: resolution.asset, media: media);
    final original = plan.original;
    final downloadable = plan.downloadable;
    return DownloadSection(
      s: s,
      original: original,
      downloadable: downloadable,
      transfer: transfer,
      downloading: _downloading,
      lookupFailed: resolution.lookupError != null,
      onDownload: () => _download(downloadable, pages: additionalOriginals),
      onRetryAvailability: () => unawaited(_retryDownloadAvailability()),
      onPause: _pause,
      onResume: _resume,
      onCancel: _cancel,
      onRetry: () => _retryDownload(downloadable),
    );
  }
}
