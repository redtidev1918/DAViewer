import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/web_session.dart';
import '../diagnostics/app_logger.dart';
import '../runtime/runtime_provider.dart';
import 'auth_controller.dart';
import 'auth_state.dart';
import 'session_state.dart';
import 'web_session_diagnostics.dart';
import 'web_session_store.dart';

/// Browser state used only by hidden website adapters. It is not a second App
/// identity and must never trigger another login prompt.
final class WebSessionState {
  const WebSessionState({this.csrf = '', this.isLoggedIn, this.username = ''});

  /// CSRF token read from a public page for website-only adapters.
  final String csrf;

  /// Whether the web session is signed in (`null` while unknown).
  final bool? isLoggedIn;

  /// The username signed in on the web (`''` when anonymous).
  final String username;
}

bool shouldStoreBackgroundBrowserSession(String csrf) => csrf.isNotEmpty;

/// Result of a cookie import. [outcome] says what happened; [username]
/// carries the imported session's username on success.
final class CookieImportResult {
  const CookieImportResult(this.outcome, {this.username = ''});

  final CookieImportOutcome outcome;
  final String username;
}

enum CookieImportOutcome {
  /// The cookies carry no DeviantArt `userinfo` session.
  anonymous,

  /// The imported session belongs to a different account than the signed-in
  /// OAuth account or the existing web session.
  accountConflict,

  /// The cookies were injected but DeviantArt did not accept them as the
  /// claimed session.
  verifyFailed,

  /// The platform cookie store is unavailable.
  unavailable,

  /// The session was injected and verified.
  success,
}

/// Identity policy for cookie import. Import is allowed only when there is no
/// signed-in identity at all, or when every existing identity matches the
/// imported session's username. Logging in is the most security-sensitive
/// flow in the app, so a mixed-account import never overwrites an existing
/// session — the user signs out first.
CookieImportOutcome? evaluateCookieImportIdentity({
  required String importedUsername,
  required String? oauthUsername,
  required String currentWebUsername,
}) {
  final imported = importedUsername.trim().toLowerCase();
  if (imported.isEmpty) return CookieImportOutcome.anonymous;
  final oauth = oauthUsername?.trim().toLowerCase() ?? '';
  if (oauth.isNotEmpty && oauth != imported) {
    return CookieImportOutcome.accountConflict;
  }
  final web = currentWebUsername.trim().toLowerCase();
  if (web.isNotEmpty && web != imported) {
    return CookieImportOutcome.accountConflict;
  }
  return null;
}

/// A Cookie snapshot can persist a session only when it contains `userinfo`
/// and that cookie names the same account as the confirmed web identity.
bool isValidCookieSnapshot({
  required List<PersistedWebCookie> cookies,
  required String username,
}) {
  if (cookies.isEmpty || username.trim().isEmpty) return false;
  final claimed = WebSession.usernameFromCookies(cookies);
  return claimed.trim().toLowerCase() == username.trim().toLowerCase();
}

/// Repairs an incomplete live store without replacing cookies the browser has
/// already rotated. Android can retain `userinfo` while losing auth cookies;
/// the identity cookie alone does not establish a complete restored session.
List<PersistedWebCookie> missingSavedWebCookies({
  required List<PersistedWebCookie> saved,
  required List<PersistedWebCookie> current,
  required DateTime now,
}) {
  String domain(PersistedWebCookie cookie) =>
      (cookie.domain ?? '').replaceFirst(RegExp(r'^\.'), '').toLowerCase();
  return saved.where((cookie) {
    if (cookie.expiresDate != null && !cookie.expiresDate!.isAfter(now)) {
      return false;
    }
    return !current.any(
      (live) =>
          live.name == cookie.name &&
          // Older Android WebViews omit domain/path metadata entirely.
          (live.domain == null ||
              cookie.domain == null ||
              (domain(live) == domain(cookie) && live.path == cookie.path)),
    );
  }).toList();
}

final webSessionControllerProvider =
    StateNotifierProvider<WebSessionController, WebSessionState>(
      (ref) => WebSessionController(ref),
    );

/// Owns the hidden browser snapshot and prevents a legacy signed-in browser
/// cookie from silently representing a different OAuth account.
final class WebSessionController extends StateNotifier<WebSessionState> {
  WebSessionController(
    this._ref, {
    WebSessionStore? store,
    CookieManager? Function()? cookieManager,
  }) : _store = store ?? const WebSessionStore(),
       _cookieManagerFactory = cookieManager,
       super(const WebSessionState());

  final Ref _ref;
  final WebSessionStore _store;
  final CookieManager? Function()? _cookieManagerFactory;
  Future<void>? _cookieRestore;
  int _identityEpoch = 0;
  int get identityEpoch => _identityEpoch;

  // Logout tombstone: a signed-in report that started before an explicit
  // logout (or while one is unresolved) must not resurrect the in-memory
  // signed-in state. [clear] bumps the revision; a report captures the
  // revision at entry and is dropped when it is stale or the tombstone is
  // unresolved; a *new* valid signed-in snapshot (or a verified restore)
  // resolves it.
  int _logoutRevision = 0;
  int _resolvedLogoutRevision = 0;
  bool get _hasUnresolvedLogout => _logoutRevision > _resolvedLogoutRevision;

  Future<void> _nativeCookieTail = Future<void>.value();
  int _cookieOperationSequence = 0;
  Future<void> get cookieMutations => _nativeCookieTail;
  bool _isCurrentIdentity(int epoch) =>
      mounted && _ref.mounted && epoch == _identityEpoch;
  CookieManager? get _nativeCookies =>
      _cookieManagerFactory?.call() ??
      _ref.read(runtimeProvider).webViewProxyManager?.cookieManager;

  Future<T> _withNativeCookies<T>(Future<T> Function() operation) {
    final id = ++_cookieOperationSequence;
    AppLogger.instance.info(
      'web-session',
      'cookie operation=$id event=queued epoch=$_identityEpoch',
    );
    final next = _nativeCookieTail.then((_) async {
      AppLogger.instance.info(
        'web-session',
        'cookie operation=$id event=started epoch=$_identityEpoch',
      );
      try {
        return await operation();
      } finally {
        AppLogger.instance.info(
          'web-session',
          'cookie operation=$id event=settled epoch=$_identityEpoch',
        );
      }
    });
    _nativeCookieTail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> initialize() async {
    final epoch = _identityEpoch;
    final saved = await _store.read();
    if (!mounted || !_ref.mounted || epoch != _identityEpoch) return;
    state = WebSessionState(
      csrf: (saved['csrf'] as String?) ?? '',
      isLoggedIn: saved['isLoggedIn'] as bool?,
      username: (saved['username'] as String?) ?? '',
    );
    // The platform WebView store can lose its cookies across an app update;
    // re-inject the persisted copy so the signed-in web session (and with it
    // the personalized feed) survives without asking the user to sign in again.
    await restorePersistedCookies();
  }

  /// Re-attempts the persisted cookie restore after an app update has already
  /// lost the live WebView cookies. The startup restore can race the WebView/
  /// proxy readiness; website-only adapters call this again when they find no
  /// live cookie header instead of surfacing a generic feed error.
  Future<void> restorePersistedCookies() {
    final active = _cookieRestore;
    if (active != null) return active;
    late final Future<void> tracked;
    tracked = _readAndRestore().whenComplete(() {
      if (identical(_cookieRestore, tracked)) _cookieRestore = null;
    });
    _cookieRestore = tracked;
    return tracked;
  }

  Future<void> _readAndRestore() async {
    final epoch = _identityEpoch;
    final saved = await _store.read();
    if (!mounted || !_ref.mounted || epoch != _identityEpoch) return;
    await _restoreWebCookies(saved);
  }

  /// Re-injects the persisted deviantart.com cookies when the WebView store
  /// is missing cookies from the saved session. Restoring requires a
  /// signed-in OAuth state; while the OAuth account profile is normally
  /// matched against the saved session's username (see
  /// [shouldRestoreSavedWebSession]), an account that is temporarily unknown —
  /// a preserved session during a flaky-network cold start — still restores,
  /// because the snapshot itself was identity-policed at write time.
  Future<void> _restoreWebCookies(Map<String, Object?> saved) async {
    final epoch = _identityEpoch;
    final rawCookies = saved['cookies'];
    // WebSessionStore.read() already decodes the snapshot (including the
    // legacy name-value migration) into PersistedWebCookies. Re-parsing that
    // decoded list returns an empty snapshot, which silently disabled the
    // whole restore.
    final cookies = rawCookies is List<PersistedWebCookie>
        ? rawCookies
        : parsePersistedCookies(rawCookies);
    if (cookies.isEmpty) {
      // Distinguishes "no persisted cookie snapshot at all" from a snapshot
      // that exists but cannot be decoded; both previously returned silently.
      AppLogger.instance.info(
        'web-session',
        'restore skipped reason=no_persisted_cookies',
      );
      return;
    }
    final savedUsername = (saved['username'] as String?)?.trim() ?? '';
    if (savedUsername.isEmpty) {
      // A cookie snapshot without a saved username can never pass the account
      // match below; surface it instead of returning silently.
      AppLogger.instance.warning(
        'web-session',
        'restore skipped reason=no_saved_username count=${cookies.length}',
      );
      return;
    }
    AppLogger.instance.info(
      'web-session',
      'restore candidate savedUsername=$savedUsername '
          'count=${cookies.length} fingerprint='
          '${webSessionPersistedFingerprint(cookies)}',
    );
    // The OAuth account profile is loaded in the background during startup
    // (AuthController deliberately does not block the splash on /user/whoami).
    // Wait for it to settle so a cold start after a platform cookie-store
    // loss restores the snapshot instead of racing the account load, seeing
    // no account yet, and skipping the re-injection entirely — which is
    // exactly the update scenario this restore exists for.
    AppLogger.instance.info(
      'web-session',
      'restore event=await_account epoch=$epoch',
    );
    await _ref.read(authControllerProvider.notifier).accountLoad;
    AppLogger.instance.info(
      'web-session',
      'restore event=account_settled epoch=$epoch',
    );
    if (!mounted || !_ref.mounted || epoch != _identityEpoch) return;
    final auth = _ref.read(authControllerProvider);
    if (!shouldRestoreSavedWebSession(
      oauthSignedIn: auth.status == AuthStatus.signedIn,
      oauthUsername: auth.account?.username,
      savedUsername: savedUsername,
    )) {
      // Signed out, or the saved session belongs to a different account:
      // never restore a web session the user has not explicitly
      // re-established.
      return;
    }
    await _withNativeCookies(() async {
      if (!_isCurrentIdentity(epoch)) return;
      try {
        final current = await _ref.read(webSessionProvider).readData();
        if (!mounted || !_ref.mounted || epoch != _identityEpoch) return;
        final liveUsername = current?.username.trim() ?? '';
        if (liveUsername.isNotEmpty &&
            liveUsername.toLowerCase() != savedUsername.toLowerCase()) {
          return; // Never mix cookies from two accounts.
        }
        final toRestore = missingSavedWebCookies(
          saved: cookies,
          current: current?.cookies ?? const <PersistedWebCookie>[],
          now: DateTime.now(),
        );
        if (toRestore.isEmpty) {
          // Previously silent. Live stores that keep a cookie *name* with a
          // rotated or invalid value are not repaired by this path, so record
          // the comparison inputs (names only, never values) to tell "nothing
          // to restore" apart from "restore never reached the store".
          AppLogger.instance.info(
            'web-session',
            'restore skipped reason=nothing_missing savedCount=${cookies.length} '
                'liveCount=${current?.cookies.length ?? 0} '
                'savedNames=[${(cookies.map((c) => c.name).toList()..sort()).join(',')}] '
                'liveNames=[${((current?.cookies ?? const <PersistedWebCookie>[]).map((c) => c.name).toList()..sort()).join(',')}]',
          );
          return;
        }
        AppLogger.instance.info(
          'web-session',
          'restore candidates count=${toRestore.length} '
              'names=[${(toRestore.map((c) => c.name).toList()..sort()).join(',')}]',
        );
        final cookieManager = _nativeCookies;
        if (cookieManager == null) {
          AppLogger.instance.warning(
            'web-session',
            'restore skipped reason=native_cookie_manager_unavailable '
                'count=${toRestore.length}',
          );
          return;
        }
        var injected = 0;
        for (final cookie in toRestore) {
          if (!mounted || !_ref.mounted || epoch != _identityEpoch) return;
          if (await _setCookie(cookieManager, cookie)) injected++;
        }
        final restored = await _ref.read(webSessionProvider).readData();
        if (!mounted || !_ref.mounted || epoch != _identityEpoch) {
          // The identity epoch moved (logout or a different account report)
          // while the writes were in flight.
          AppLogger.instance.info(
            'web-session',
            'restore readback skipped reason=identity_changed '
                'injected=$injected',
          );
          return;
        }
        if (restored == null) {
          AppLogger.instance.warning(
            'web-session',
            'restore readback failed reason=cookie_store_unavailable '
                'injected=$injected',
          );
        } else if (restored.username.isEmpty) {
          // The store accepted the writes but the read-back no longer names an
          // identity (e.g. Android truncating the userinfo value). Names only.
          AppLogger.instance.warning(
            'web-session',
            'restore readback no_identity count=${restored.cookies.length} '
                'names=[${(restored.cookies.map((c) => c.name).toList()..sort()).join(',')}] '
                'userinfoPresent=${restored.cookies.any((c) => c.name == 'userinfo')}',
          );
        } else {
          AppLogger.instance.info(
            'web-session',
            'restore verified username=${restored.username} '
                'count=${restored.cookies.length} '
                'fingerprint=${restored.fingerprint}',
          );
          state = WebSessionState(
            csrf: state.csrf,
            isLoggedIn: true,
            username: restored.username,
          );
          // A verified restore is a fresh signed-in establishment: it
          // resolves any logout tombstone from an earlier explicit logout.
          _resolvedLogoutRevision = _logoutRevision;
          await _store.update(
            isLoggedIn: true,
            username: restored.username,
            isCurrent: () => _isCurrentIdentity(epoch),
          );
        }
      } on Object catch (error) {
        // Best effort; a failed restore only means the user signs in again.
        // The type (never the message) is recorded so the next device capture
        // can distinguish a store write failure from a read failure.
        AppLogger.instance.warning(
          'web-session',
          'restore failed errorType=${error.runtimeType}',
        );
      }
    });
  }

  /// Records the user-visible login result. The Cookie map must come from the
  /// same read as [username]; the controller never takes a second Cookie
  /// snapshot because that race was the cause of empty first-login snapshots.
  ///
  /// A signed-in report without a valid snapshot still updates runtime state,
  /// but leaves the last good persisted snapshot untouched. It will be replaced
  /// later by [ensurePersistentSnapshot] once the WebView read is usable.
  Future<void> report({
    required String csrf,
    required String username,
    List<PersistedWebCookie>? capturedCookies,
  }) async {
    final loggedIn = username.isNotEmpty;
    // Tombstone: capture the logout revision so a report racing an explicit
    // logout can be dropped at the write-back branches below.
    final logoutRevision = _logoutRevision;
    if (loggedIn && username.toLowerCase() != state.username.toLowerCase()) {
      _identityEpoch++;
    }
    final epoch = _identityEpoch;
    final oauthUsername = _ref.read(authControllerProvider).account?.username;
    if (loggedIn &&
        oauthUsername != null &&
        oauthUsername.isNotEmpty &&
        username.toLowerCase() != oauthUsername.toLowerCase()) {
      try {
        await _withNativeCookies(() async {
          if (_isCurrentIdentity(epoch)) {
            await _nativeCookies?.deleteAllCookies();
          }
        });
      } on Object {
        // Best effort.
      }
      if (!_isCurrentIdentity(epoch)) return;
      state = const WebSessionState(isLoggedIn: false);
      await _store.clear(reason: 'identity_mismatch');
      return;
    }

    // A transient anonymous page (a login-page load before the signed-in
    // redirect, a bot challenge, or an early cookie-store read) must never
    // downgrade a session already confirmed signed in. Only explicit logout
    // clears the confirmed identity and its persisted snapshot.
    if (shouldPreserveSignedInSessionOnAnonymousProbe(
      currentlySignedIn: state.isLoggedIn == true,
      probeUsername: username,
    )) {
      if (csrf.isNotEmpty) {
        state = WebSessionState(
          csrf: csrf,
          isLoggedIn: true,
          username: state.username,
        );
        await _store.update(
          csrf: csrf,
          isLoggedIn: true,
          username: state.username,
          isCurrent: () => _isCurrentIdentity(epoch),
        );
      }
      return;
    }

    // Tombstone gate: a signed-in report that started before the explicit
    // logout (or while its cleanup is still unresolved) must not resurrect
    // the in-memory signed-in state. Only a *new* valid signed-in snapshot
    // after a fresh login resolves the tombstone (see the write-back branch
    // below and the restore-verified path).
    final freshOAuthIdentity =
        _ref.read(authControllerProvider).status == AuthStatus.signedIn &&
        oauthUsername?.isNotEmpty == true &&
        oauthUsername!.toLowerCase() == username.toLowerCase();
    final validSnapshot = isValidCookieSnapshot(
      cookies: capturedCookies ?? const <PersistedWebCookie>[],
      username: username,
    );
    if (loggedIn &&
        (_logoutRevision != logoutRevision ||
            (_hasUnresolvedLogout &&
                (!freshOAuthIdentity || !validSnapshot)))) {
      AppLogger.instance.warning(
        'web-session',
        'stale signed-in report dropped reason=post_logout_no_snapshot '
            'claimedUsername=$username',
      );
      return;
    }

    if (loggedIn && !validSnapshot) {
      state = WebSessionState(csrf: csrf, isLoggedIn: true, username: username);
      AppLogger.instance.warning(
        'web-session',
        'persist skipped reason='
            '${capturedCookies == null || capturedCookies.isEmpty ? 'empty_capture' : 'missing_userinfo'} '
            'claimedUsername=$username captured=${capturedCookies?.length ?? 0}',
      );
      return;
    }

    state = WebSessionState(
      csrf: csrf,
      isLoggedIn: loggedIn,
      username: username,
    );
    if (loggedIn) {
      // A fresh, valid signed-in snapshot from a new login resolves any
      // earlier logout tombstone.
      _resolvedLogoutRevision = _logoutRevision;
    }
    await _store.update(
      csrf: csrf,
      isLoggedIn: loggedIn,
      username: username,
      cookies: loggedIn ? capturedCookies : null,
      isCurrent: () => _isCurrentIdentity(epoch),
    );
  }

  /// Captures and persists a valid live Cookie snapshot. This is the bounded
  /// retry path for a login whose first WebView read was unavailable/empty; it
  /// runs from health checks only while the runtime still reports signed in.
  Future<bool> ensurePersistentSnapshot({
    List<PersistedWebCookie>? capturedCookies,
  }) async {
    if (state.isLoggedIn != true) return false;
    final epoch = _identityEpoch;
    final username = state.username;
    final cookies =
        capturedCookies ??
        (await _ref.read(webSessionProvider).readData())?.cookies ??
        const <PersistedWebCookie>[];
    if (!_isCurrentIdentity(epoch)) return false;
    if (!isValidCookieSnapshot(cookies: cookies, username: username)) {
      AppLogger.instance.warning(
        'web-session',
        'persist skipped reason=invalid_snapshot '
            'claimedUsername=${state.username} count=${cookies.length}',
      );
      return false;
    }
    final savedCookies = (await _store.read())['cookies'];
    if (!_isCurrentIdentity(epoch)) return false;
    final persisted = savedCookies is List<PersistedWebCookie>
        ? savedCookies
        : parsePersistedCookies(savedCookies);
    if (webSessionPersistedFingerprint(persisted) ==
        webSessionPersistedFingerprint(cookies)) {
      return true;
    }
    await _store.update(
      csrf: state.csrf,
      isLoggedIn: true,
      username: state.username,
      cookies: cookies,
      isCurrent: () => _isCurrentIdentity(epoch),
    );
    return _isCurrentIdentity(epoch);
  }

  /// Stores a fresh public browser CSRF even without a `userinfo` cookie.
  /// This supports public website metadata fallbacks without asking the user
  /// for a second login after OAuth. An empty CSRF still never overwrites a
  /// valid snapshot.
  ///
  /// A hidden probe landing on an anonymous page (bot challenge, transient
  /// empty cookie-store read, redirect before session cookies are re-injected)
  /// must never flip a known signed-in web session to signed-out — the feeds
  /// would then demand a login the user already has (see docs/authentication:
  /// an incomplete page never means signed out). Anonymous probe results
  /// therefore rotate the CSRF only and leave the session identity and cookie
  /// snapshot intact.
  /// Rotates the CSRF token from a background browser context. This is the
  /// ONLY thing a background probe may write: it never touches identity,
  /// cookies, or any session verdict (REG-010).
  Future<void> updateCsrf(String csrf, {int? expectedEpoch}) async {
    final epoch = expectedEpoch ?? _identityEpoch;
    if (!_isCurrentIdentity(epoch)) return;
    if (!shouldStoreBackgroundBrowserSession(csrf)) return;
    state = WebSessionState(
      csrf: csrf,
      isLoggedIn: state.isLoggedIn,
      username: state.username,
    );
    await _store.update(csrf: csrf, isCurrent: () => _isCurrentIdentity(epoch));
  }

  /// Snapshots the current deviantart.com cookies with their metadata.
  Future<List<PersistedWebCookie>> _captureCookies() async {
    try {
      final snapshot = await _ref
          .read(webSessionProvider)
          .snapshot(source: 'capture-before');
      AppLogger.instance.info('web-session', snapshot.logLine());
      final cookieManager = _nativeCookies;
      if (cookieManager == null) return const <PersistedWebCookie>[];
      final cookies = await cookieManager.getCookies(
        url: WebUri('https://www.deviantart.com/'),
      );
      return <PersistedWebCookie>[
        for (final cookie in cookies)
          PersistedWebCookie.fromBrowserCookie(cookie),
      ];
    } on Object {
      return const <PersistedWebCookie>[];
    }
  }

  /// Imports externally provided deviantart.com cookies into the web session
  /// and persists them once DeviantArt confirms the session.
  ///
  /// Identity is checked before anything is written (see
  /// [evaluateCookieImportIdentity]): an import that would create a
  /// mixed-account session is rejected. After injection the imported username
  /// is read back from the cookie store; if it does not match, the previous
  /// cookies are restored so a failed import never leaves a partial or
  /// attacker-controlled session. The caller triggers a CSRF refresh
  /// afterwards so website adapters pick up the new session.
  Future<CookieImportResult> importCookies(Map<String, String> cookies) {
    final epoch = _identityEpoch;
    return _withNativeCookies(() => _importCookies(cookies, epoch));
  }

  Future<CookieImportResult> _importCookies(
    Map<String, String> cookies,
    int epoch,
  ) async {
    if (!_isCurrentIdentity(epoch)) {
      return const CookieImportResult(CookieImportOutcome.accountConflict);
    }
    final importedUsername = WebSession.usernameFromUserInfo(
      cookies['userinfo'],
    );
    final oauthUsername = _ref.read(authControllerProvider).account?.username;
    String currentWebUsername = '';
    try {
      currentWebUsername =
          (await _ref.read(webSessionProvider).readData())?.username ?? '';
    } on Object {
      // The cookie store may be unavailable; that is handled below.
    }
    if (!_isCurrentIdentity(epoch)) {
      return const CookieImportResult(CookieImportOutcome.accountConflict);
    }
    final gate = evaluateCookieImportIdentity(
      importedUsername: importedUsername,
      oauthUsername: oauthUsername,
      currentWebUsername: currentWebUsername,
    );
    if (gate != null) {
      return CookieImportResult(gate, username: importedUsername);
    }

    final cookieManager = _nativeCookies;
    if (cookieManager == null) {
      return const CookieImportResult(CookieImportOutcome.unavailable);
    }
    // Snapshot the live cookies so a failed verification can roll back instead
    // of leaving the injected (possibly bad) session in place.
    final previousCookies = await _captureCookies();
    if (!_isCurrentIdentity(epoch)) {
      return const CookieImportResult(CookieImportOutcome.accountConflict);
    }
    try {
      for (final entry in cookies.entries) {
        if (!_isCurrentIdentity(epoch)) {
          return const CookieImportResult(CookieImportOutcome.accountConflict);
        }
        await cookieManager.setCookie(
          url: WebUri('https://www.deviantart.com/'),
          name: entry.key,
          value: entry.value,
        );
      }
      final verified = await _ref.read(webSessionProvider).readData();
      if (!_isCurrentIdentity(epoch)) {
        return const CookieImportResult(CookieImportOutcome.accountConflict);
      }
      final verifiedUser = verified?.username ?? '';
      final sameAccount =
          verifiedUser.isNotEmpty &&
          verifiedUser.trim().toLowerCase() ==
              importedUsername.trim().toLowerCase();
      if (!sameAccount) {
        // Re-importing the app's own live session (identical `userinfo`
        // value) can fail the read-back on stores that normalize cookie
        // values on write (Android `getCookie` truncation, macOS cookie
        // re-creation). The session was not changed by this import — the
        // claimed session is already live, so nothing was rejected. Treat it
        // as success instead of rolling back a working session and reporting
        // a spurious rejection.
        if (isUnchangedSessionReimport(
          previous: previousCookies,
          imported: cookies,
        )) {
          state = WebSessionState(
            csrf: state.csrf,
            isLoggedIn: true,
            username: importedUsername,
          );
          await _store.update(
            csrf: state.csrf,
            isLoggedIn: true,
            username: importedUsername,
            cookies: parsePersistedCookies(cookies),
            isCurrent: () => _isCurrentIdentity(epoch),
          );
          return CookieImportResult(
            CookieImportOutcome.success,
            username: importedUsername,
          );
        }
        await _rollbackCookies(cookieManager, previousCookies, epoch);
        return const CookieImportResult(CookieImportOutcome.verifyFailed);
      }
      state = WebSessionState(
        csrf: state.csrf,
        isLoggedIn: true,
        username: verifiedUser,
      );
      await _store.update(
        csrf: state.csrf,
        isLoggedIn: true,
        username: verifiedUser,
        cookies: parsePersistedCookies(cookies),
        isCurrent: () => _isCurrentIdentity(epoch),
      );
      return CookieImportResult(
        CookieImportOutcome.success,
        username: verifiedUser,
      );
    } on Object {
      await _rollbackCookies(cookieManager, previousCookies, epoch);
      return const CookieImportResult(CookieImportOutcome.unavailable);
    }
  }

  /// Restores the live cookie store to [previous] after a failed import.
  Future<void> _rollbackCookies(
    CookieManager cookieManager,
    List<PersistedWebCookie> previous,
    int epoch,
  ) async {
    try {
      if (!_isCurrentIdentity(epoch)) return;
      await cookieManager.deleteAllCookies();
      for (final cookie in previous) {
        if (!_isCurrentIdentity(epoch)) return;
        await _setCookie(cookieManager, cookie);
      }
    } on Object {
      // Best effort; a failed rollback only means the user re-signs-in.
    }
  }

  /// Writes one persisted cookie back into the WebView store. Host-only
  /// `www.deviantart.com` cookies are restored without a domain attribute so
  /// they stay host-only; parent-domain cookies (`.deviantart.com`) keep their
  /// domain, path, expiry, and security flags. Returns whether the platform
  /// store accepted the write, so callers can count real writes, not attempts.
  Future<bool> _setCookie(
    CookieManager cookieManager,
    PersistedWebCookie cookie,
  ) async {
    final hostOnly =
        cookie.domain == null ||
        cookie.domain!.isEmpty ||
        cookie.domain == 'www.deviantart.com';
    final accepted = await cookieManager.setCookie(
      url: WebUri('https://www.deviantart.com/'),
      name: cookie.name,
      value: cookie.value,
      path: cookie.path.isEmpty ? '/' : cookie.path,
      domain: hostOnly ? null : cookie.domain,
      expiresDate: cookie.expiresDate?.millisecondsSinceEpoch,
      isSecure: cookie.isSecure,
      isHttpOnly: cookie.isHttpOnly,
    );
    if (accepted != true) {
      // The platform store can refuse a write; record the name only and let
      // the read-back decide the overall outcome.
      AppLogger.instance.warning(
        'web-session',
        'cookie write rejected name=${cookie.name}',
      );
    }
    return accepted == true;
  }

  Future<void> clear() async {
    _identityEpoch++;
    // Raise the logout tombstone: signed-in reports captured before this
    // point are dropped until a fresh valid snapshot resolves it.
    _logoutRevision++;
    _cookieRestore = null;
    state = const WebSessionState(isLoggedIn: false);
    final nativeClear = _withNativeCookies(() async {
      try {
        await _nativeCookies?.deleteAllCookies();
      } on Object catch (error) {
        AppLogger.instance.warning(
          'web-session',
          'explicit logout native clear failed errorType=${error.runtimeType}',
        );
      }
    });
    await Future.wait([nativeClear, _store.clear(reason: 'explicit_logout')]);
  }

  /// The persisted deviantart.com cookie snapshot, used as a fallback when the
  /// live WebView store cannot be read (e.g. cookie export during early
  /// startup). Returns an empty list when nothing is stored.
  Future<List<PersistedWebCookie>> persistedCookies() async {
    final cookies = (await _store.read())['cookies'];
    return cookies is List<PersistedWebCookie>
        ? cookies
        : parsePersistedCookies(cookies);
  }
}

/// Whether the persisted web session may be restored for the current OAuth
/// identity. Restoring requires a signed-in OAuth state (a signed-out user is
/// never silently given a web session, which would dismiss the login screen
/// before OAuth completes). When the OAuth account is known it must match the
/// saved session's username; when the account is temporarily unknown — a
/// preserved session during a flaky-network cold start — the restore is
/// allowed, because the snapshot itself was identity-policed at write time
/// and [report] re-checks identity against the live web session afterwards.
bool shouldRestoreSavedWebSession({
  required bool oauthSignedIn,
  required String? oauthUsername,
  required String savedUsername,
}) {
  if (!oauthSignedIn) return false;
  final oauth = oauthUsername?.trim().toLowerCase() ?? '';
  if (oauth.isEmpty) return true;
  return savedUsername.trim().toLowerCase() == oauth;
}

/// Whether an anonymous report must leave the current web session in place:
/// an anonymous page (a login-page load before the signed-in redirect, a bot
/// challenge, a transiently empty cookie-store read, or a redirect that ran
/// before the persisted cookies were re-injected) must never downgrade a
/// session already known to be signed in. Only explicit logout via [clear]
/// transitions a confirmed session to anonymous/signed-out.
bool shouldPreserveSignedInSessionOnAnonymousProbe({
  required bool currentlySignedIn,
  required String probeUsername,
}) => probeUsername.isEmpty && currentlySignedIn;

/// Whether an import is a no-op re-import of the app's own live session: the
/// previous session carried the exact same `userinfo` value. Such an import
/// cannot be rejected — the session it claims is already live.
bool isUnchangedSessionReimport({
  required List<PersistedWebCookie> previous,
  required Map<String, String> imported,
}) {
  final importedUser = imported['userinfo'];
  if (importedUser == null || importedUser.isEmpty) return false;
  return previous.any(
    (cookie) => cookie.name == 'userinfo' && cookie.value == importedUser,
  );
}
