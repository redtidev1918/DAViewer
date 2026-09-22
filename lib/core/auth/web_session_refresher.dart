import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dakit_web/dakit_web.dart';

import '../runtime/runtime_provider.dart';
import 'session_state.dart';
import 'web_session_controller.dart';

/// Loads a public page in a hidden browser so website-only metadata adapters
/// can obtain the anonymous CSRF/cookies expected by DeviantArt. It never asks
/// the user to log in and is not part of App authentication.
final webSessionRefresherProvider = Provider<WebSessionRefresher>(
  (ref) => WebSessionRefresher(ref),
);

final class WebSessionRefresher {
  WebSessionRefresher(this._ref);

  final Ref _ref;
  HeadlessInAppWebView? _headless;
  bool _running = false;
  Timer? _timeout;
  Completer<void>? _completion;

  /// Loads `www.deviantart.com` headlessly and reports a fresh CSRF token.
  /// Concurrent callers share the same operation, and the returned future does
  /// not complete until the page reports a token or the safety timeout fires.
  Future<void> refresh() async {
    final active = _completion;
    if (_running && active != null) {
      await active.future;
      return;
    }
    _running = true;
    final completion = Completer<void>();
    _completion = completion;
    try {
      final runtime = _ref.read(runtimeProvider);
      final environment = await runtime.webViewProxyManager?.prepare();
      final headless = HeadlessInAppWebView(
        webViewEnvironment: environment,
        initialSize: const Size(480, 800),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: webUserAgent,
        ),
        initialUrlRequest: URLRequest(
          url: WebUri('https://www.deviantart.com/'),
        ),
        onLoadStop: (controller, url) async {
          if (url == null || url.host != 'www.deviantart.com') return;
          await _report(controller);
          await _dispose();
        },
        onReceivedError: (controller, request, error) async {
          await _dispose();
        },
      );
      _headless = headless;
      await headless.run();
      // Safety net in case navigation never completes.
      if (_running) {
        _timeout = Timer(const Duration(seconds: 20), () {
          if (_running) unawaited(_dispose());
        });
      }
    } on Object catch (error, stack) {
      debugPrint('[web-session] headless refresh failed: $error');
      debugPrintStack(stackTrace: stack);
      await _dispose();
    }
    await completion.future;
  }

  Future<void> _report(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(
        source: "JSON.stringify({csrf: window.__CSRF_TOKEN__ || ''})",
      );
      if (raw is! String || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final csrf = (data['csrf'] as String?) ?? '';
      // A public browser session is sufficient for numeric-id and website
      // metadata fallbacks. It is intentionally not treated as another user
      // login; the official OAuth session remains the only app identity.
      if (csrf.isEmpty) return;
      final username =
          (await _ref.read(webSessionProvider).readData())?.username ?? '';
      debugPrint(
        '[web-session] cold-start csrf=${csrf.length} username=$username',
      );
      await _ref
          .read(webSessionControllerProvider.notifier)
          .reportRefresh(csrf: csrf, username: username);
    } on Object catch (error) {
      debugPrint('[web-session] headless report failed: $error');
    }
  }

  Future<void> _dispose() async {
    _timeout?.cancel();
    _timeout = null;
    final headless = _headless;
    _headless = null;
    if (headless != null) {
      try {
        await headless.dispose();
      } on Object {
        // Best effort.
      }
    }
    final completion = _completion;
    _completion = null;
    _running = false;
    if (completion != null && !completion.isCompleted) {
      completion.complete();
    }
  }
}
