import 'package:daviewer/core/feed/personalized_request_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? decision({
    bool mounted = true,
    bool account = true,
    bool epoch = true,
    bool request = true,
    bool healthy = true,
    bool generation = true,
    bool credentials = true,
    bool generic = false,
  }) => personalizedResultDiscardReason(
    mounted: mounted,
    sameAccount: account,
    sameEpoch: epoch,
    sameRequest: request,
    healthy: healthy,
    sameGeneration: generation,
    sameCredentials: credentials,
    generic: generic,
  );
  test(
    'stable verified response is accepted',
    () => expect(decision(), isNull),
  );
  test('verified same-account recovery adopts a usable old response', () {
    expect(decision(generation: false, credentials: false), isNull);
  });
  test('same-account confirmation alone does not waste a usable response', () {
    expect(decision(generation: false), isNull);
  });
  test('same-generation credential rotation adopts the response (RC3)', () {
    // A same-generation rotation means no login/lockout/account transition
    // happened — the server (or this app's own same-session probe) rotated
    // cookies for the very session the request belongs to. Discarding that
    // was self-inflicted pagination damage (2026-10-14 runtime-stability
    // audit); identity-relevant changes bump the generation instead.
    expect(decision(credentials: false), isNull);
  });
  test('account switch including away-and-back rejects stale response', () {
    expect(decision(account: false), 'account_changed');
    expect(decision(epoch: false), 'account_changed');
  });
  test('newer request and disposed provider have explicit discard reasons', () {
    expect(decision(request: false), 'newer_request_won');
    expect(decision(mounted: false), 'provider_disposed');
  });
  test('expired session cannot adopt a transport success', () {
    expect(decision(healthy: false), 'session_superseded');
  });
  test('generic old response cannot revive a cleared incident', () {
    expect(decision(generation: false, generic: true), 'session_superseded');
    expect(decision(generic: true), 'generic_fallback');
  });
}
