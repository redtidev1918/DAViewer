import 'package:dakit_flutter/dakit_flutter.dart';

import 'download_reason.dart';

/// The single decision point for what the download button offers.
final class DownloadPlan {
  const DownloadPlan({
    required this.original,
    required this.downloadable,
    required this.usingFallback,
  });

  /// Authoritative original-file probe result (may be unavailable).
  final MediaAsset original;

  /// The asset the button will actually request: the original when it can be
  /// transferred, otherwise the highest-quality displayed image fallback.
  final MediaAsset downloadable;

  final bool usingFallback;

  bool get canDownload => downloadable.canTransfer;
}

/// Plans an image download from the original probe and displayed media.
DownloadPlan planDownload({
  required MediaAsset original,
  required List<MediaAsset> media,
}) {
  if (original.canTransfer) {
    return DownloadPlan(
      original: original,
      downloadable: original,
      usingFallback: false,
    );
  }
  // Only image artworks may fall back to the highest-quality displayed image.
  // A video poster must never make a restricted video look downloadable.
  final fallback = bestFallbackImage(media) ?? original;
  return DownloadPlan(
    original: original,
    downloadable: fallback,
    usingFallback: !original.canTransfer && fallback.canTransfer,
  );
}
