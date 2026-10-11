import 'package:daviewer/core/network/system_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWindowsProxyServer', () {
    test('parses a single endpoint', () {
      expect(
        parseWindowsProxyServer('127.0.0.1:7892')?.toString(),
        '127.0.0.1:7892',
      );
    });

    test('prefers https in a protocol-specific value', () {
      final value = parseWindowsProxyServer(
        'http=127.0.0.1:7890;https=127.0.0.1:7892;socks=127.0.0.1:7891',
      );
      expect(value?.toString(), '127.0.0.1:7892');
    });

    test('rejects unusable values', () {
      expect(parseWindowsProxyServer('socks=127.0.0.1:7891'), isNull);
      expect(parseWindowsProxyServer('http='), isNull);
    });
  });
}
