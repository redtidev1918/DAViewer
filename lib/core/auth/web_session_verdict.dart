import 'web_session_refresher.dart' show WebSessionProbeOutcome;
import 'web_session_status.dart' show WebSessionStatusState;

/// Who observed a piece of web-session evidence. Only these sources exist;
/// every verdict must name one, so logs and tests can always answer
/// "which path changed the state".
enum WebSessionEvidenceSource {
  /// The explicit login WebView (user-initiated). Strongest evidence.
  webLogin,

  /// A bare HTTP fetch of the home page (WAF-sensitive, non-authoritative
  /// about logged-out).
  bareProbe,

  /// The real headless browser (same cookie stack as login).
  realBrowserProbe,

  /// The local cookie store / identity state (not a server answer).
  localState,
}

/// One observed fact about the web session. Evidence never mutates state
/// itself; [resolveWebSessionVerdict] turns it into a verdict decision.
final class WebSessionEvidence {
  const WebSessionEvidence({
    required this.source,
    required this.outcome,
    this.username = '',
    required this.generation,
  });

  final WebSessionEvidenceSource source;
  final WebSessionProbeOutcome outcome;

  /// The username the observation rendered ('' when none was rendered).
  final String username;

  /// The verification generation this evidence belongs to. Stale evidence
  /// (generation no longer current) is always discarded by the controller.
  final int generation;
}

/// The outcome of applying evidence to the current verdict. [nextState] null
/// means "keep the current verdict".
final class WebSessionVerdictDecision {
  const WebSessionVerdictDecision.keep()
    : nextState = null,
      serverUsername = '',
      escalateToRealBrowser = false;

  const WebSessionVerdictDecision.transition(
    this.nextState, {
    this.serverUsername = '',
  }) : escalateToRealBrowser = false;

  const WebSessionVerdictDecision.escalate()
    : nextState = null,
      serverUsername = '',
      escalateToRealBrowser = true;

  final WebSessionStatusState? nextState;
  final String serverUsername;
  final bool escalateToRealBrowser;
}

/// The single transition policy for web-session verdicts.
///
/// Hard rules (REG-009/010):
/// - a bare anonymous answer while a WebView-confirmed session is claimed
///   never becomes "logged out" on its own — it escalates to the real browser;
/// - a real-browser anonymous answer IS authoritative about logged-out;
/// - a real-browser unavailable answer is never a logged-out signal;
/// - a confirmed username that does not match the claimed identity is
///   anonymous regardless of which probe produced it.
WebSessionVerdictDecision resolveWebSessionVerdict({
  required WebSessionStatusState current,
  required WebSessionEvidence evidence,
  required String claimedUsername,
  required bool claimedSignedIn,
}) {
  final claimed = claimedUsername.trim().toLowerCase();
  final observed = evidence.username.trim();
  final matchesClaim = claimed.isNotEmpty && observed.toLowerCase() == claimed;

  switch (evidence.source) {
    case WebSessionEvidenceSource.webLogin:
      // Explicit user login: a confirmed username is a healthy verdict.
      return evidence.outcome == WebSessionProbeOutcome.confirmed
          ? WebSessionVerdictDecision.transition(
              WebSessionStatusState.healthy,
              serverUsername: observed,
            )
          : const WebSessionVerdictDecision.keep();

    case WebSessionEvidenceSource.bareProbe:
      switch (evidence.outcome) {
        case WebSessionProbeOutcome.confirmed:
          return matchesClaim
              ? WebSessionVerdictDecision.transition(
                  WebSessionStatusState.healthy,
                  serverUsername: observed,
                )
              : const WebSessionVerdictDecision.transition(
                  WebSessionStatusState.anonymous,
                );
        case WebSessionProbeOutcome.anonymous:
          // A claimed signed-in session must be arbitrated by the real
          // browser before any logged-out verdict.
          return claimedSignedIn && claimed.isNotEmpty
              ? const WebSessionVerdictDecision.escalate()
              : const WebSessionVerdictDecision.transition(
                  WebSessionStatusState.anonymous,
                );
        case WebSessionProbeOutcome.unavailable:
          return const WebSessionVerdictDecision.transition(
            WebSessionStatusState.unavailable,
          );
      }

    case WebSessionEvidenceSource.realBrowserProbe:
      switch (evidence.outcome) {
        case WebSessionProbeOutcome.confirmed:
          return matchesClaim
              ? WebSessionVerdictDecision.transition(
                  WebSessionStatusState.healthy,
                  serverUsername: observed,
                )
              : const WebSessionVerdictDecision.transition(
                  WebSessionStatusState.anonymous,
                );
        case WebSessionProbeOutcome.anonymous:
          return const WebSessionVerdictDecision.transition(
            WebSessionStatusState.anonymous,
          );
        case WebSessionProbeOutcome.unavailable:
          // Challenge/network: stay non-committal, never logged out.
          return const WebSessionVerdictDecision.transition(
            WebSessionStatusState.unverified,
          );
      }

    case WebSessionEvidenceSource.localState:
      switch (evidence.outcome) {
        case WebSessionProbeOutcome.confirmed:
          return const WebSessionVerdictDecision.keep();
        case WebSessionProbeOutcome.anonymous:
          // No usable cookie header / no claimed identity.
          return const WebSessionVerdictDecision.transition(
            WebSessionStatusState.anonymous,
          );
        case WebSessionProbeOutcome.unavailable:
          return const WebSessionVerdictDecision.transition(
            WebSessionStatusState.unavailable,
          );
      }
  }
}
