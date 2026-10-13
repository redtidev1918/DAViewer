import 'dart:async';
import 'dart:convert';

import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:daviewer/core/auth/web_session_refresher.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/core/auth/session_state.dart';
import 'package:daviewer/core/data/web_session.dart';
import 'package:daviewer/core/auth/web_session_diagnostics.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends Fake implements InAppWebViewController {
  int reloads = 0;
  @override
  Future<void> reload() async => reloads++;
  String? username;
  String csrf = '';
  bool challenge = false;
  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.deviantart.com/');
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => jsonEncode({
    'origin': 'https://www.deviantart.com',
    'username': username,
    'csrf': csrf,
    'challenge': challenge,
  });
}

class _Cookies extends Fake implements CookieManager {
  String value = 'transaction-test';
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    InAppWebViewController? iosBelow11WebViewController,
  }) async => [Cookie(name: 'context', value: value)];
}

class _Browser extends PlatformHeadlessInAppWebView {
  _Browser(super.params) : super.implementation();

  final startup = Completer<void>();
  final teardown = Completer<void>();

  @override
  Future<void> run() => startup.future;

  @override
  Future<void> dispose() => teardown.future;

  void fail({required bool mainFrame}) {
    params.onReceivedError?.call(
      _Controller(),
      WebResourceRequest(
        url: WebUri('https://www.deviantart.com/'),
        isForMainFrame: mainFrame,
      ),
      WebResourceError(
        type: WebResourceErrorType.UNKNOWN,
        description: 'offline',
      ),
    );
  }
}

class _Platform extends InAppWebViewPlatform {
  final browsers = <_Browser>[];

  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
    PlatformHeadlessInAppWebViewCreationParams params,
  ) {
    final browser = _Browser(params);
    browsers.add(browser);
    return browser;
  }
}

void main() {
  late _Platform platform;
  late ProviderContainer container;
  late _Cookies cookies;
  InAppWebViewPlatform? originalPlatform;
  final transfers = BackgroundTransferManager(diagnostics: AppLogger.instance);

  setUp(() {
    originalPlatform = InAppWebViewPlatform.instance;
    platform = _Platform();
    cookies = _Cookies();
    InAppWebViewPlatform.instance = platform;
    container = ProviderContainer(
      overrides: [
        webSessionProvider.overrideWithValue(WebSession(() => cookies)),
        runtimeProvider.overrideWithValue(
          AppRuntime(
            clientId: 'test',
            oauth: null,
            transport: null,
            transfers: transfers,
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    for (final browser in platform.browsers) {
      if (!browser.startup.isCompleted) browser.startup.complete();
      if (!browser.teardown.isCompleted) browser.teardown.complete();
    }
    if (originalPlatform != null) {
      InAppWebViewPlatform.instance = originalPlatform;
    }
  });

  testWidgets(
    'native host waits past a CSRF-only stop and observes asynchronous identity',
    (tester) async {
      var finished = false;
      final probe = container.read(webSessionRefresherProvider).refresh();
      unawaited(probe.then((_) => finished = true));
      await tester.pump();
      final browser = platform.browsers.single;
      final page = _Controller()..csrf = 'token';
      browser.params.onWebViewCreated?.call(page);
      browser.params.onLoadStop?.call(
        page,
        WebUri('https://www.deviantart.com/'),
      );
      await tester.pump();
      expect(finished, isFalse);
      page.username = 'artist';
      await tester.pump(const Duration(milliseconds: 500));
      expect((await probe).username, 'artist');
    },
  );

  testWidgets(
    'native headless callbacks require reload commit, not SPA history or a stale stop',
    (tester) async {
      var finished = false;
      final probe = container.read(webSessionRefresherProvider).refresh();
      unawaited(probe.then((_) => finished = true));
      await tester.pump();
      final browser = platform.browsers.single;
      final page = _Controller()
        ..username = 'anonymous'
        ..csrf = 'token';
      final url = WebUri('https://www.deviantart.com/');
      browser.params.onWebViewCreated?.call(page);
      browser.params.onLoadStart?.call(page, url);
      browser.params.onLoadStop?.call(page, url);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(page.reloads, 1);
      expect(finished, isFalse);
      browser.params.onUpdateVisitedHistory?.call(page, url, false);
      await tester.pump();
      browser.params.onLoadStop?.call(page, url); // Duplicate old stop.
      await tester.pump();
      expect(finished, isFalse);
      browser.params.onLoadStart?.call(page, url);
      browser.params.onLoadStop?.call(page, url);
      await tester.pump();
      final result = await probe;
      expect(result.outcome, WebSessionProbeOutcome.anonymous);
      expect(
        result.credentialFingerprint,
        cookieHeaderFingerprint('context=transaction-test'),
      );
      cookies.value = 'later-unverified-store';
      expect(
        result.credentialFingerprint,
        isNot(cookieHeaderFingerprint('context=${cookies.value}')),
      );
    },
  );

  testWidgets(
    'native host tolerates more than three challenge stops and SPA recovery',
    (tester) async {
      var finished = false;
      final probe = container.read(webSessionRefresherProvider).refresh();
      unawaited(probe.then((_) => finished = true));
      await tester.pump();
      final browser = platform.browsers.single;
      final page = _Controller()..challenge = true;
      browser.params.onWebViewCreated?.call(page);
      for (var i = 0; i < 5; i++) {
        browser.params.onLoadStart?.call(
          page,
          WebUri('https://www.deviantart.com/'),
        );
        browser.params.onLoadStop?.call(
          page,
          WebUri('https://www.deviantart.com/'),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(finished, isFalse);
      }
      page.challenge = false;
      page.username = 'artist';
      browser.params.onUpdateVisitedHistory?.call(
        page,
        WebUri('https://www.deviantart.com/'),
        false,
      );
      await tester.pump();
      expect((await probe).outcome, WebSessionProbeOutcome.confirmed);
    },
  );

  testWidgets(
    'visible handoff releases hidden callers and rejects late page identity',
    (tester) async {
      final host = container.read(webSessionRefresherProvider);
      final probe = host.refresh();
      await tester.pump();
      final browser = platform.browsers.single;
      final page = _Controller();
      browser.params.onWebViewCreated?.call(page);
      unawaited(host.yieldToVisible());
      expect((await probe).outcome, WebSessionProbeOutcome.unavailable);
      page.username = 'artist';
      browser.params.onLoadStop?.call(
        page,
        WebUri('https://www.deviantart.com/'),
      );
      await tester.pump(const Duration(seconds: 21));
      expect(platform.browsers, hasLength(1));
    },
  );

  testWidgets('account change starts a fresh host and discards old callbacks', (
    tester,
  ) async {
    final host = container.read(webSessionRefresherProvider);
    final old = host.refresh();
    await tester.pump();
    final oldBrowser = platform.browsers.single;
    unawaited(host.accountChanged());
    expect((await old).outcome, WebSessionProbeOutcome.unavailable);
    final current = host.refresh();
    await tester.pump();
    expect(platform.browsers, hasLength(2));
    oldBrowser.params.onWebViewCreated?.call(_Controller()..username = 'old');
    oldBrowser.fail(mainFrame: true);
    final newBrowser = platform.browsers.last;
    newBrowser.params.onWebViewCreated?.call(_Controller()..username = 'new');
    await tester.pump();
    expect((await current).username, 'new');
  });

  testWidgets('startup timeout returns before a stalled browser teardown', (
    tester,
  ) async {
    final refresher = container.read(webSessionRefresherProvider);
    final first = refresher.refresh();
    final shared = refresher.refresh();
    await tester.pump();
    expect(platform.browsers, hasLength(1));
    await tester.pump(const Duration(seconds: 21));
    expect((await first).outcome, WebSessionProbeOutcome.unavailable);
    expect((await shared).outcome, WebSessionProbeOutcome.unavailable);
    expect(platform.browsers.first.teardown.isCompleted, isFalse);

    var finished = false;
    final retry = refresher.refresh();
    unawaited(retry.then((_) => finished = true));
    await tester.pump();
    expect(platform.browsers, hasLength(2));
    platform.browsers.first.fail(mainFrame: true);
    await tester.pump();
    expect(
      finished,
      isFalse,
      reason: 'old callbacks cannot terminate a new probe',
    );
    platform.browsers.last.fail(mainFrame: true);
    await tester.pump();
    expect((await retry).outcome, WebSessionProbeOutcome.unavailable);
  });

  testWidgets('subresource errors do not terminate the session probe', (
    tester,
  ) async {
    var finished = false;
    final probe = container.read(webSessionRefresherProvider).refresh();
    unawaited(probe.then((_) => finished = true));
    await tester.pump();
    final browser = platform.browsers.single;
    browser.fail(mainFrame: false);
    await tester.pump();
    expect(finished, isFalse);
    browser.fail(mainFrame: true);
    await tester.pump();
    expect((await probe).outcome, WebSessionProbeOutcome.unavailable);
  });

  testWidgets('provider disposal releases callers waiting for the probe', (
    tester,
  ) async {
    final probe = container.read(webSessionRefresherProvider).refresh();
    await tester.pump();
    container.dispose();
    await tester.pump();
    expect((await probe).outcome, WebSessionProbeOutcome.unavailable);
  });
}
