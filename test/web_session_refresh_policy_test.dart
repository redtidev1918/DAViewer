import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public browser CSRF is stored without requiring another login', () {
    expect(shouldStoreBackgroundBrowserSession('csrf'), isTrue);
  });

  test('empty background page cannot overwrite the browser session', () {
    expect(shouldStoreBackgroundBrowserSession(''), isFalse);
  });
}
