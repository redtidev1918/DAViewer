import 'package:dakit_flutter/dakit_flutter.dart';

import '../../core/l10n/app_strings.dart';

/// Returns the view-level gate for an artwork, or `null` when no asset is
/// locked. "Not downloadable" is deliberately not a gate: NSFW or creator-
/// disabled art is still viewable, so it must never carry a lock badge.
MediaAvailability? artworkViewLock(Artwork artwork) {
  for (final asset in artwork.media) {
    if (asset.role == MediaRole.preview && _isViewGate(asset.availability)) {
      return asset.availability;
    }
  }
  if (_isViewGate(artwork.downloadAvailability)) {
    return artwork.downloadAvailability;
  }
  return null;
}

bool _isViewGate(MediaAvailability availability) =>
    availability == MediaAvailability.purchaseRequired ||
    availability == MediaAvailability.restricted ||
    availability == MediaAvailability.loginRequired;

/// A blurred server preview is not evidence of a purchase requirement. Resolve
/// it through the signed-in detail endpoint instead of editing the CDN URL.
bool needsArtworkMediaHydration(Artwork artwork) =>
    artwork.media.any((asset) => isBlurredPreview(asset)) ||
    (artwork.isMature &&
        artworkViewLock(artwork) == MediaAvailability.purchaseRequired);

bool isBlurredPreview(MediaAsset asset) =>
    asset.role == MediaRole.preview &&
    (asset.uri?.path.contains('blur_') ?? false);

bool hasClearArtworkPreview(Artwork artwork) => artwork.media.any(
  (asset) =>
      asset.role == MediaRole.preview &&
      asset.availability == MediaAvailability.available &&
      asset.uri != null &&
      !isBlurredPreview(asset),
);

/// Short user-facing label for a locked preview/detail.
String artworkViewLockLabel(AppStrings s, MediaAvailability availability) =>
    switch (availability) {
      MediaAvailability.purchaseRequired => s.viewLockedSubscription,
      MediaAvailability.restricted => s.availabilityRestricted,
      MediaAvailability.loginRequired => s.availabilityLoginRequired,
      _ => s.availabilityUnavailable,
    };
