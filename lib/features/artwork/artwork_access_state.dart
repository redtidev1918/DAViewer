import 'package:dakit_core/dakit_core.dart';

import 'artwork_access.dart';

enum ArtworkRestriction {
  matureLogin,

  /// Requires explicit browsing-policy evidence, never an inferred reason.
  matureSettings,
  purchase,
  subscription,
  blocked,
  deleted,
  login,
  unknown,
}

enum ArtworkAccessSource { mappedList, webList, webDetail, officialDetail }

enum ArtworkPreviewState { missing, blurred, clear }

enum ArtworkAccessPhase { unresolved, checking, confirmed, retryableFailure }

/// Access evidence is scoped to a source. OAuth main-image access does not
/// establish access to additional pages served by the web session.
final class ArtworkAccessEvidence {
  ArtworkAccessEvidence({
    required this.source,
    required this.preview,
    required Iterable<ArtworkRestriction> restrictions,
    this.grantsAccess = false,
    Iterable<String> unknownReasons = const <String>[],
  }) : restrictions = Set<ArtworkRestriction>.unmodifiable(restrictions),
       unknownReasons = List<String>.unmodifiable(unknownReasons);

  final ArtworkAccessSource source;
  final ArtworkPreviewState preview;
  final Set<ArtworkRestriction> restrictions;
  final List<String> unknownReasons;
  final bool grantsAccess;

  bool get isCanonical =>
      source == ArtworkAccessSource.webDetail ||
      source == ArtworkAccessSource.officialDetail;

  bool get isConclusive =>
      isCanonical &&
      (grantsAccess ||
          (restrictions.isNotEmpty &&
              !restrictions.contains(ArtworkRestriction.unknown)));

  bool get requestsSessionCheck =>
      (source == ArtworkAccessSource.mappedList &&
          preview == ArtworkPreviewState.blurred) ||
      restrictions.contains(ArtworkRestriction.matureLogin) ||
      restrictions.contains(ArtworkRestriction.login) ||
      (preview == ArtworkPreviewState.blurred &&
          (restrictions.isEmpty ||
              restrictions.contains(ArtworkRestriction.unknown)));

  MediaAvailability? get viewGate {
    if (restrictions.contains(ArtworkRestriction.deleted) ||
        restrictions.contains(ArtworkRestriction.blocked)) {
      return MediaAvailability.restricted;
    }
    if (restrictions.contains(ArtworkRestriction.purchase) ||
        restrictions.contains(ArtworkRestriction.subscription)) {
      return MediaAvailability.purchaseRequired;
    }
    if (restrictions.contains(ArtworkRestriction.matureLogin) ||
        restrictions.contains(ArtworkRestriction.login)) {
      return MediaAvailability.loginRequired;
    }
    return restrictions.isEmpty ? null : MediaAvailability.restricted;
  }

  factory ArtworkAccessEvidence.fromArtwork(
    Artwork artwork, {
    ArtworkAccessSource source = ArtworkAccessSource.mappedList,
  }) {
    final gate = artworkViewLock(artwork);
    final restrictions = <ArtworkRestriction>{
      if (gate == MediaAvailability.purchaseRequired)
        ArtworkRestriction.purchase,
      if (gate == MediaAvailability.loginRequired) ArtworkRestriction.login,
      if (gate == MediaAvailability.restricted) ArtworkRestriction.blocked,
    };
    final preview = artworkPreviewState(artwork);
    return ArtworkAccessEvidence(
      source: source,
      preview: preview,
      restrictions: restrictions,
      grantsAccess:
          source != ArtworkAccessSource.mappedList &&
          source != ArtworkAccessSource.webList &&
          preview == ArtworkPreviewState.clear &&
          restrictions.isEmpty,
    );
  }

  factory ArtworkAccessEvidence.fromWeb(
    Map<Object?, Object?> raw,
    Artwork artwork, {
    required ArtworkAccessSource source,
  }) {
    final restrictions = <ArtworkRestriction>{};
    final unknownReasons = <String>[];
    final reasons = raw['blockReasons'] ?? raw['block_reasons'];
    if (reasons is List) {
      for (final reason in reasons) {
        // Only observed reason codes receive a specific interpretation.
        if (reason == 'mature_loggedout') {
          restrictions.add(ArtworkRestriction.matureLogin);
        } else {
          restrictions.add(ArtworkRestriction.unknown);
          unknownReasons.add('$reason');
        }
      }
    }
    if (raw['isDeleted'] == true) {
      restrictions.add(ArtworkRestriction.deleted);
    } else if (raw['isBlocked'] == true && restrictions.isEmpty) {
      restrictions.add(ArtworkRestriction.blocked);
    }
    final premium = raw['premiumFolderData'] ?? raw['premium_folder_data'];
    if (premium is Map &&
        (premium['hasAccess'] ?? premium['has_access']) == false) {
      restrictions.add(ArtworkRestriction.purchase);
    }
    final tier = raw['tierAccess'] ?? raw['tier_access'];
    if (tier == 'locked' || tier == 'locked-subscribed') {
      restrictions.add(ArtworkRestriction.subscription);
    }
    final preview = artworkPreviewState(artwork);
    return ArtworkAccessEvidence(
      source: source,
      preview: preview,
      restrictions: restrictions,
      unknownReasons: unknownReasons,
      grantsAccess:
          source == ArtworkAccessSource.webDetail &&
          preview == ArtworkPreviewState.clear &&
          restrictions.isEmpty &&
          artworkViewLock(artwork) == null,
    );
  }
}

ArtworkPreviewState artworkPreviewState(Artwork artwork) {
  // Available poster thumbnails may coexist with a gated display-size image.
  // Inspect all previews rather than treating the first poster as a grant.
  if (artwork.media.any(isBlurredPreview)) {
    return ArtworkPreviewState.blurred;
  }
  if (hasClearArtworkPreview(artwork)) return ArtworkPreviewState.clear;
  return ArtworkPreviewState.missing;
}

final class ArtworkAccessState {
  const ArtworkAccessState({
    this.phase = ArtworkAccessPhase.unresolved,
    this.listEvidence,
    this.webDetailEvidence,
    this.officialDetailEvidence,
  });

  final ArtworkAccessPhase phase;
  final ArtworkAccessEvidence? listEvidence;
  final ArtworkAccessEvidence? webDetailEvidence;
  final ArtworkAccessEvidence? officialDetailEvidence;

  ArtworkAccessEvidence? get mainEvidence {
    final official = officialDetailEvidence;
    if (official?.isConclusive ?? false) return official;
    final web = webDetailEvidence;
    if (web?.isConclusive ?? false) return web;
    return web ?? listEvidence ?? official;
  }

  Set<ArtworkRestriction> get mainRestrictions =>
      mainEvidence?.restrictions ?? const <ArtworkRestriction>{};

  Set<ArtworkRestriction> get webRestrictions =>
      (webDetailEvidence ?? listEvidence)?.restrictions ??
      const <ArtworkRestriction>{};

  bool get needsResolution =>
      phase != ArtworkAccessPhase.confirmed &&
      (mainEvidence?.preview == ArtworkPreviewState.blurred ||
          mainRestrictions.isNotEmpty);

  ArtworkAccessState withPhase(ArtworkAccessPhase phase) => ArtworkAccessState(
    phase: phase,
    listEvidence: listEvidence,
    webDetailEvidence: webDetailEvidence,
    officialDetailEvidence: officialDetailEvidence,
  );

  ArtworkAccessState observe(ArtworkAccessEvidence evidence) {
    final next = ArtworkAccessState(
      phase: phase,
      listEvidence: evidence.source == ArtworkAccessSource.mappedList
          ? listEvidence?.source == ArtworkAccessSource.webList
                ? listEvidence
                : evidence
          : evidence.source == ArtworkAccessSource.webList
          ? evidence
          : listEvidence,
      webDetailEvidence: evidence.source == ArtworkAccessSource.webDetail
          ? evidence
          : webDetailEvidence,
      officialDetailEvidence:
          evidence.source == ArtworkAccessSource.officialDetail
          ? evidence
          : officialDetailEvidence,
    );
    return next;
  }
}
