import 'dart:async';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_logger.dart';
import '../l10n/app_strings.dart';
import '../runtime/app_runtime.dart';
import '../runtime/runtime_provider.dart';
import '../settings/app_preferences.dart';
import 'auth_state.dart';
import 'web_session_controller.dart';

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref),
);

/// Only the absence/revocation of credentials is allowed to force sign-out.
/// Network, upstream and Keychain failures are recoverable and must not turn a
/// temporarily unreachable persisted session into a destructive first-run
/// experience.
bool shouldPreserveSessionAfterRestoreFailure(Object error) {
  if (error is TimeoutException) return true;
  if (error is! DAKitException) return true;
  return !isDefinitiveCredentialFailure(error);
}

/// A recorded explicit logout must never be undone by a leftover secure-storage
/// token. Unknown/missing evidence keeps the legacy token-restore path so a
/// first install or an unreadable preferences file does not sign a user out.
bool shouldRestoreOAuthSessionAfterEvidence(OAuthSessionEvidence evidence) =>
    evidence != OAuthSessionEvidence.signedOut;

/// DeviantArt has returned both RFC `invalid_grant` and the non-standard
/// `invalid_request: The refresh_token is invalid` for a revoked refresh token.
/// Treat both as definitive so cold start cannot preserve a fake signed-in
/// state and retry every Home request indefinitely. The legacy shape remains
/// here even after DAKit normalization so upgrades from an older SDK are safe.
bool isDefinitiveCredentialFailure(DAKitException error) {
  if (error.code == 'oauth.session.missing' ||
      error.code == 'oauth.refresh.missing' ||
      error.code == 'oauth.refresh.invalid' ||
      error.code.contains('invalid_grant')) {
    return true;
  }
  if (error.kind != DAKitFailureKind.authentication ||
      error.code != 'oauth.provider.invalid_request') {
    return false;
  }
  final description =
      '${error.details['provider_description'] ?? error.message}'
          .replaceAll('_', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
  return description.contains('refresh token') &&
      (description.contains('invalid') || description.contains('revoked'));
}

/// Owns the app's single user sign-in lifecycle. Hidden public browser state is
/// managed separately by [WebSessionController] and is never authentication.
final class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref)
    : super(const AuthState(status: AuthStatus.unknown)) {
    _sessionInvalidationSubscription = _ref
        .read(runtimeProvider)
        .oauth
        ?.session
        .invalidations
        .listen((error) => unawaited(_handleSessionInvalidation(error)));
  }

  final Ref _ref;
  StreamSubscription<DAKitException>? _sessionInvalidationSubscription;
  bool _initializing = false;
  bool _loggingIn = false;
  Future<void>? _loginOperation;
  Future<void>? _accountLoad;

  AppRuntime get _runtime => _ref.read(runtimeProvider);
  AppLogger get _log => AppLogger.instance;

  Future<void> initialize() async {
    if (_initializing || state.status != AuthStatus.unknown) return;
    _initializing = true;

    final runtime = _runtime;
    if (runtime.isConfigured && runtime.oauth != null) {
      try {
        // 1. Resume an interrupted OAuth transaction (e.g. cold-start callback
        //    from the system browser). Returns null when there is nothing to
        //    resume, which is the normal case on every regular restart.
        final restored = await runtime.oauth!.resumePending(
          waitForCallback: false,
        );
        if (restored != null) {
          _log.info('auth', 'initialize: resumed pending OAuth login');
          // Sign in immediately; the account profile loads in the background
          // so the splash can hand off to Home without waiting on /user/whoami.
          state = const AuthState(status: AuthStatus.signedIn);
          unawaited(_startAccountLoad(runtime));
          _initializing = false;
          return;
        }

        // 2. A recorded explicit logout is authoritative even when
        //    secure-storage cleanup failed: the user asked to leave, so a
        //    leftover local token must never revive the signed-in UI on the
        //    next launch. `unknown` keeps the old behavior for fresh installs
        //    and unreadable preferences.
        final evidence = await AppPreferences.loadOAuthSessionEvidence();
        if (!shouldRestoreOAuthSessionAfterEvidence(evidence)) {
          _log.info(
            'auth',
            'initialize: explicit logout recorded; not restoring OAuth',
          );
          try {
            await runtime.oauth!.session.logout(revoke: false);
          } on Object catch (error, stack) {
            _log.warning(
              'auth',
              'initialize: stale OAuth token clear failed',
              error,
              stack,
            );
          }
          _initializing = false;
          return;
        }

        // 3. Restore the persisted token. Transient failures preserve the
        //    session; a definitive credential error moves to signed-out, and
        //    the web login screen re-verifies OAuth before it rebuilds the
        //    web Cookie.
        final tokens = await runtime.oauth!
            .validTokens(forceRefresh: false)
            .timeout(const Duration(seconds: 15));
        _log.info(
          'auth',
          'initialize: restored persisted session '
              '(expires ${tokens.expiresAt.toUtc().toIso8601String()})',
        );
        await AppPreferences.saveOAuthSessionKnown(true);
        state = const AuthState(status: AuthStatus.signedIn);
        unawaited(_startAccountLoad(runtime));
        _initializing = false;
        return;
      } on DAKitException catch (error) {
        if (shouldPreserveSessionAfterRestoreFailure(error)) {
          // Network / storage / timeout failure while restoring a stored
          // token: stay signed in instead of claiming a logged-out state.
          _log.warning(
            'auth',
            'initialize: persisted session temporarily unavailable; '
                'preserving signed-in state',
            error,
          );
          // Still try the profile: it is independent of the token check and
          // may succeed on the next attempt; identity-dependent cold-start
          // steps (web-session cookie restore) await [accountLoad].
          unawaited(_startAccountLoad(runtime));
          state = const AuthState(status: AuthStatus.signedIn);
          _initializing = false;
          return;
        }
        if (isDefinitiveCredentialFailure(error)) {
          // DAKit clears the rejected token before emitting its invalidation.
          // Do not call logout again: a Keychain deletion denial must not
          // create a second generation change during the next authorization.
          await AppPreferences.saveOAuthSessionKnown(false);
        }
        _log.info('auth', 'initialize: authorization is required', error);
      } on Object catch (error, stack) {
        // A timeout or unexpected error during restore means a stored token
        // exists and a network operation hung — preserve the session rather
        // than logging the user out.
        _log.warning(
          'auth',
          'initialize: session restore failed transiently; preserving state',
          error,
          stack,
        );
        // Same as the DAKit case: try the profile anyway so the web-session
        // cookie restore can verify (or at least not be skipped by) identity.
        unawaited(_startAccountLoad(runtime));
        state = const AuthState(status: AuthStatus.signedIn);
        _initializing = false;
        return;
      }
    }

    state = const AuthState(status: AuthStatus.signedOut);
    _initializing = false;
  }

  Future<void> _handleSessionInvalidation(DAKitException error) async {
    _log.info(
      'auth',
      'provider invalidated the saved OAuth session; sign-in is required',
      error,
    );
    await AppPreferences.saveOAuthSessionKnown(false);
    state = const AuthState(status: AuthStatus.signedOut);
  }

  /// Starts the standard OAuth browser flow.
  Future<void> login() {
    if (state.status == AuthStatus.signedIn) return Future<void>.value();
    final active = _loginOperation;
    if (active != null) return active;

    late final Future<void> tracked;
    tracked = _performLogin().whenComplete(() {
      if (identical(_loginOperation, tracked)) _loginOperation = null;
    });
    _loginOperation = tracked;
    return tracked;
  }

  /// Starts a fresh OAuth login from the login screen. A stale in-flight
  /// transaction from an earlier visit must never block the new one, otherwise
  /// the user can complete the WebView login but the app stays signed out.
  Future<void> retryLogin() async {
    if (state.status == AuthStatus.signedIn) return;
    await cancelLogin();
    await login();
  }

  /// Confirms the OAuth token is still accepted by DeviantArt, forcing one
  /// refresh so a server-revoked token cannot keep the signed-in UI alive.
  /// Transient network/storage failures keep the session; a definitive
  /// credential failure signs out so the same WebView login can restore both.
  Future<bool> confirmOAuthSession() async {
    final runtime = _runtime;
    if (!runtime.isConfigured || runtime.oauth == null) return false;
    try {
      await runtime.oauth!
          .validTokens(forceRefresh: true)
          .timeout(const Duration(seconds: 15));
      await AppPreferences.saveOAuthSessionKnown(true);
      return true;
    } on DAKitException catch (error) {
      if (isDefinitiveCredentialFailure(error)) {
        await AppPreferences.saveOAuthSessionKnown(false);
        state = const AuthState(status: AuthStatus.signedOut);
        return false;
      }
      _log.warning(
        'auth',
        'oauth confirm temporarily unavailable; keeping session',
        error,
      );
      return true;
    } on Object catch (error, stack) {
      _log.warning(
        'auth',
        'oauth confirm failed transiently; keeping session',
        error,
        stack,
      );
      return true;
    }
  }

  Future<void> _performLogin() async {
    final runtime = _runtime;
    if (!runtime.isConfigured || runtime.oauth == null) {
      _log.warning('auth', 'OAuth login requires DAKIT_CLIENT_ID');
      state = AuthState(
        status: AuthStatus.signedOut,
        error: strings(_ref.read(appLanguageProvider)).oauthClientIdMissing,
      );
      return;
    }
    if (state.status == AuthStatus.signedIn || _loggingIn) return;

    _loggingIn = true;
    state = AuthState(
      status: state.status,
      account: state.account,
      isLoggingIn: true,
    );
    try {
      _log.info('auth', 'login: starting OAuth authorize');
      await runtime.oauth!.authorize();
      await AppPreferences.saveOAuthSessionKnown(true);
      _log.info('auth', 'login: authorize returned, loading account');
      await _loadAccount(runtime);
    } on DAKitException catch (error) {
      if (error.kind == DAKitFailureKind.cancelled ||
          error.code == 'oauth.transaction.cancelled') {
        _log.info('auth', 'OAuth login cancelled cleanly');
        state = const AuthState(status: AuthStatus.signedOut);
        return;
      }
      _log.error('auth', 'OAuth login failed: ${error.code}', error);
      state = AuthState(status: AuthStatus.signedOut, error: error);
    } catch (error, stack) {
      _log.error('auth', 'OAuth login failed (unexpected)', error, stack);
      state = AuthState(status: AuthStatus.signedOut, error: error);
    } finally {
      _loggingIn = false;
    }
  }

  /// Ends an abandoned PKCE transaction and waits until single-flight state is
  /// clear, so the next login creates a new authorize URL immediately.
  Future<void> cancelLogin() async {
    if (state.status == AuthStatus.signedIn) return;
    final runtime = _runtime;
    final active = _loginOperation;
    if (runtime.oauth != null) {
      try {
        await runtime.oauth!.authorization.cancelPending();
      } on Object catch (error, stack) {
        _log.warning(
          'auth',
          'could not cancel pending OAuth login',
          error,
          stack,
        );
      }
    }
    if (active != null) {
      try {
        await active.timeout(const Duration(seconds: 2));
      } on Object {
        // The cancellation signal is authoritative. Do not keep the UI busy
        // merely because an old callback future is slow to unwind.
      }
    }
    _loggingIn = false;
    _loginOperation = null;
    if (state.status != AuthStatus.signedIn) {
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  Future<void> logout() async {
    final runtime = _runtime;
    // Persist the user's intent and leave authenticated UI before best-effort
    // network revocation or secure-storage cleanup. Neither failure may sign
    // the user back in on the next launch.
    state = const AuthState(status: AuthStatus.signedOut);
    await AppPreferences.saveOAuthSessionKnown(false);
    if (runtime.isConfigured && runtime.oauth != null) {
      try {
        _log.info('auth', 'logout: revoking oauth session');
        await runtime.oauth!.logout(revoke: true);
      } on Object catch (error, stack) {
        _log.warning('auth', 'logout: revocation failed', error, stack);
        // Clear the session directly so the next authorize starts clean.
        try {
          await runtime.oauth!.session.logout(revoke: false);
        } on Object catch (error2, stack2) {
          _log.warning('auth', 'logout: token clear failed', error2, stack2);
        }
      }
    }
    // Clear the embedded web session too (cookies + snapshot + state).
    try {
      await runtime.webViewProxyManager?.cookieManager.deleteAllCookies();
    } on Object catch (error, stack) {
      _log.warning('auth', 'logout: web cookie clear failed', error, stack);
    }
    await _ref.read(webSessionControllerProvider.notifier).clear();
  }

  /// Starts the background account profile load once and memoizes its future,
  /// so identity-dependent cold-start steps can await it instead of racing a
  /// still-loading account.
  Future<void> _startAccountLoad(AppRuntime runtime) =>
      _accountLoad ??= _loadAccount(runtime);

  /// Completes when the initial account profile load settles (account loaded,
  /// or the load failed and signed-in state has no account).
  Future<void> get accountLoad => _accountLoad ?? Future<void>.value();

  Future<void> _loadAccount(AppRuntime runtime) async {
    _log.info('auth', 'loading account');
    try {
      final account = await OfficialAccountRepository(runtime.transport!)
          .currentUser()
          .timeout(const Duration(seconds: 15));
      _log.info('auth', 'account loaded: ${account.username}');
      state = AuthState(status: AuthStatus.signedIn, account: account);
    } on DAKitException catch (error, stack) {
      if (isDefinitiveCredentialFailure(error)) {
        await AppPreferences.saveOAuthSessionKnown(false);
        state = const AuthState(status: AuthStatus.signedOut);
        return;
      }
      _log.error('auth', 'account load failed', error, stack);
      // Tokens are still valid even if the profile fetch failed; stay signed
      // in with an unknown profile instead of forcing a logout.
      state = const AuthState(status: AuthStatus.signedIn);
    } on Object catch (error, stack) {
      _log.error('auth', 'account load failed', error, stack);
      state = const AuthState(status: AuthStatus.signedIn);
    }
  }

  @override
  void dispose() {
    unawaited(_sessionInvalidationSubscription?.cancel());
    super.dispose();
  }
}
