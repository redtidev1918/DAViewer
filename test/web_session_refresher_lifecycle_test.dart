import 'dart:async';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/auth/web_session_refresher.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends Fake implements InAppWebViewController {}

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
  InAppWebViewPlatform? originalPlatform;
  final transfers = BackgroundTransferManager(diagnostics: AppLogger.instance);

  setUp(() {
    originalPlatform = InAppWebViewPlatform.instance;
    platform = _Platform();
    InAppWebViewPlatform.instance = platform;
    container = ProviderContainer(
      overrides: [
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
