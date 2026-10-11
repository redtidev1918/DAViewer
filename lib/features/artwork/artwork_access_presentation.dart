import 'package:dakit_core/dakit_core.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import 'artwork_access_state.dart';

/// UI reports the observed cause without deriving payment from blur/maturity.
({String label, IconData icon})? artworkAccessPresentation(
  Artwork artwork,
  ArtworkAccessState? state,
  AppStrings s,
) {
  final evidence =
      state?.mainEvidence ?? ArtworkAccessEvidence.fromArtwork(artwork);
  final restrictions = evidence.restrictions;
  if (restrictions.isEmpty) {
    return evidence.preview == ArtworkPreviewState.blurred
        ? (label: s.previewRestrictionUnknown, icon: Icons.help_outline)
        : null;
  }
  final labels = <String>{
    for (final restriction in restrictions)
      switch (restriction) {
        ArtworkRestriction.matureLogin => s.matureLoginRequired,
        ArtworkRestriction.matureSettings => s.matureSettingsRestricted,
        ArtworkRestriction.purchase ||
        ArtworkRestriction.subscription => s.viewLockedSubscription,
        ArtworkRestriction.login => s.availabilityLoginRequired,
        ArtworkRestriction.blocked => s.availabilityRestricted,
        ArtworkRestriction.deleted => s.availabilityMissing,
        ArtworkRestriction.unknown => s.previewRestrictionUnknown,
      },
  };
  final icon =
      restrictions.contains(ArtworkRestriction.purchase) ||
          restrictions.contains(ArtworkRestriction.subscription)
      ? Icons.lock_outline
      : restrictions.contains(ArtworkRestriction.matureLogin) ||
            restrictions.contains(ArtworkRestriction.matureSettings)
      ? Icons.visibility_off_outlined
      : restrictions.contains(ArtworkRestriction.unknown)
      ? Icons.help_outline
      : Icons.block;
  return (label: labels.join(' · '), icon: icon);
}
