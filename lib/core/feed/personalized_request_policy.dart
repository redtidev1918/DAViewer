/// Pure ownership policy. A newer verified same-account session can adopt a
/// non-generic response from its recovery transaction. Unknown credential
/// changes and generic responses retain the conservative rejection rule.
///
/// Credential rotation *within the same generation* no longer discards a
/// response: same-generation means no login/lockout/account transition
/// happened, so a changed Cookie header is the server (or this app's own
/// same-session probe navigation) rotating cookies for the very session the
/// request belongs to. Rejecting that was self-inflicted pagination damage
/// (RC3, 2026-10-14); identity-relevant changes bump the generation and stay
/// rejected below.
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
  if (generic) return 'generic_fallback';
  return null;
}
