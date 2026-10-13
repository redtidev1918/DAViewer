/// Pure ownership policy. A newer verified same-account session can adopt a
/// non-generic response from its recovery transaction. Unknown credential
/// changes and generic responses retain the conservative rejection rule.
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
