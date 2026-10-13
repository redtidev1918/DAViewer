/// Pure ownership policy. A newer verified same-account session can adopt a
/// non-generic response from its recovery transaction. Generic responses
/// retain the conservative rejection rule.
///
/// `sameCredentials` means "unchanged since the request started, OR rotated to
/// a set the verdict chain has server-confirmed" — the caller computes the
/// verified-rotation case against the status controller's
/// `verifiedCredentialFingerprint` (review R2, REG-024). A rotation with no
/// matching confirmation passes `sameCredentials: false` and is rejected:
/// same-generation means no login/lockout/account transition happened, so an
/// unexplained credential change stays conservative while rotations caused by
/// this app's own same-session probe navigation (which the probe itself
/// authenticated) no longer discard in-flight pages (RC3, 2026-10-14).
/// Identity-relevant changes bump the generation and stay rejected below.
String? personalizedResultDiscardReason({
  required bool mounted,
  required bool sameAccount,
  required bool sameEpoch,
  required bool sameRequest,
  required bool healthy,
  required bool sameGeneration,
  required bool sameCredentials,
  required bool generic,
}) {
  if (!mounted) return 'provider_disposed';
  if (!sameAccount || !sameEpoch) return 'account_changed';
  if (!sameRequest) return 'newer_request_won';
  if (!healthy) return 'session_superseded';
  if (!sameGeneration && generic) return 'session_superseded';
  if (!sameCredentials && sameGeneration) return 'credentials_changed';
  if (generic) return 'generic_fallback';
  return null;
}
