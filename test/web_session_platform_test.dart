import 'package:daviewer/core/auth/web_session_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android uses the real WebView UA, not the desktop Chrome UA', () {
    expect(webLoginUserAgent(isAndroid: true), isNull);
  });

  test('desktop keeps the desktop Chrome UA', () {
    final desktop = webLoginUserAgent(isAndroid: false);
    expect(desktop, isNotNull);
    expect(desktop, contains('Chrome'));
  });
}
