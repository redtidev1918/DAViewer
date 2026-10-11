import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artwork_access_state.dart';

final artworkAccessControllerProvider =
    NotifierProvider<ArtworkAccessController, Map<String, ArtworkAccessState>>(
      ArtworkAccessController.new,
    );

/// Owns content evidence and lookup progress, never an authentication verdict.
final class ArtworkAccessController
    extends Notifier<Map<String, ArtworkAccessState>> {
  int _sessionEpoch = 0;

  int get sessionEpoch => _sessionEpoch;

  @override
  Map<String, ArtworkAccessState> build() => <String, ArtworkAccessState>{};

  ArtworkAccessState forId(String id) =>
      state[id] ?? const ArtworkAccessState();

  void observe(String id, ArtworkAccessEvidence evidence, {int? epoch}) {
    if (epoch != null && epoch != _sessionEpoch) return;
    state = <String, ArtworkAccessState>{
      ...state,
      id: forId(id).observe(evidence),
    };
  }

  int beginResolution(String id) {
    _setPhase(id, ArtworkAccessPhase.checking);
    return _sessionEpoch;
  }

  void confirm(String id, ArtworkAccessEvidence evidence, int epoch) {
    if (epoch != _sessionEpoch || !evidence.isConclusive) return;
    observe(id, evidence, epoch: epoch);
    _setPhase(id, ArtworkAccessPhase.confirmed);
  }

  void resolutionFailed(String id, int epoch) {
    if (epoch != _sessionEpoch) return;
    if (forId(id).phase == ArtworkAccessPhase.confirmed) return;
    _setPhase(id, ArtworkAccessPhase.retryableFailure);
  }

  void resetSession() {
    _sessionEpoch++;
    state = <String, ArtworkAccessState>{};
  }

  void retainIds(Set<String> ids) {
    state = <String, ArtworkAccessState>{
      for (final entry in state.entries)
        if (ids.contains(entry.key)) entry.key: entry.value,
    };
  }

  void _setPhase(String id, ArtworkAccessPhase phase) {
    state = <String, ArtworkAccessState>{
      ...state,
      id: forId(id).withPhase(phase),
    };
  }
}
