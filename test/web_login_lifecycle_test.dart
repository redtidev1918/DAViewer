import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/auth/webview_oauth_bridge.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/web_login/web_login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _LifecyclePlatform extends InAppWebViewPlatform {
  int controllerCreateCalls = 0;
  int reloadCalls = 0;
  InAppWebViewController? controller;
  PlatformInAppWebViewWidgetCreationParams? params;
  final Set<String> _activatedKeys = <String>{};

  bool activateOnce(Key? key) {
    final id = key?.toString() ?? '<none>';
    return _activatedKeys.add(id);
  }

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewController(
    PlatformInAppWebViewControllerCreationParams params,
  ) {
    controllerCreateCalls += 1;
    return _LifecycleController(params, this);
  }

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() {
    return _LifecycleController(
      const PlatformInAppWebViewControllerCreationParams(id: 'static'),
      this,
    );
  }

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return _LifecycleWidget(params, this);
  }

  Future<void> triggerLoadStop() async {
    final controller = this.controller;
    final params = this.params;
    if (controller == null || params == null) return;
    params.onLoadStop?.call(
      controller,
      WebUri('https://www.deviantart.com/users/login'),
    );
  }
}

final class _LifecycleWidget extends PlatformInAppWebViewWidget {
  _LifecycleWidget(super.params, this.platform) : super.implementation();

  final _LifecyclePlatform platform;
  @override
  Widget build(BuildContext context) {
    if (platform.activateOnce(params.key)) {
      final controller = params.controllerFromPlatform!(
        platform.createPlatformInAppWebViewController(
          PlatformInAppWebViewControllerCreationParams(
            id: 'webview',
            webviewParams: params,
          ),
        ),
      );
      platform.controller = controller;
      platform.params = params;
      params.onWebViewCreated?.call(controller);
    }
    return const SizedBox.expand();
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) {
    return params.controllerFromPlatform!(controller) as T;
  }

  @override
  void dispose() {}
}

final class _LifecycleController extends PlatformInAppWebViewController {
  _LifecycleController(super.params, this.platform) : super.implementation();

  final _LifecyclePlatform platform;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains('document.body')) {
      return 'Max challenge attempts exceeded';
    }
    return '{"csrf":"fake-token"}';
  }

  @override
  Future<void> reload() async {
    platform.reloadCalls += 1;
  }
}

void main() {
  testWidgets(
    'rebuild and challenge banner never recreate or reload the WebView',
    (tester) async {
      final platform = _LifecyclePlatform();
      InAppWebViewPlatform.instance = platform;
      final rebuild = ValueNotifier<int>(0);
      addTearDown(rebuild.dispose);
      final runtime = AppRuntime(
        clientId: '',
        oauth: null,
        transport: null,
        transfers: BackgroundTransferManager(diagnostics: AppLogger.instance),
        webViewOAuthBridge: WebViewOAuthBridge(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[runtimeProvider.overrideWithValue(runtime)],
          child: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (context, value, child) =>
                MaterialApp(home: WebLoginScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(platform.controllerCreateCalls, 1);
      await platform.triggerLoadStop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Max challenge attempts exceeded'),
        findsOneWidget,
      );

      rebuild.value += 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(platform.controllerCreateCalls, 1);
      expect(platform.reloadCalls, 0);
    },
  );
}
