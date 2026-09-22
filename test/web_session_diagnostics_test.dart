import 'package:daviewer/core/auth/web_session_diagnostics.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot log never contains cookie values', () {
    final snapshot = cookieSnapshot(
      source: 'test',
      cookies: <Cookie>[
        Cookie(name: 'userinfo', value: 'top-secret-value'),
        Cookie(name: 'csrf', value: 'another-secret'),
      ],
    );

    final line = snapshot.logLine();
    expect(line, isNot(contains('top-secret-value')));
    expect(line, isNot(contains('another-secret')));
    expect(line, contains('fingerprint='));
  });

  test('fingerprint is stable and sensitive to values', () {
    List<Cookie> cookies(String value) => <Cookie>[
      Cookie(name: 'a', value: value),
      Cookie(name: 'b', value: 'b'),
    ];

    final first = webSessionFingerprint(cookies('x'));
    final same = webSessionFingerprint(cookies('x'));
    final changed = webSessionFingerprint(cookies('y'));

    expect(first, same);
    expect(first, isNot(changed));
  });

  test('header fingerprint and count are value-safe', () {
    const header = 'userinfo=secret; csrf=token';
    expect(cookieHeaderCount(header), 2);
    expect(cookieHeaderFingerprint(header), cookieHeaderFingerprint(header));
    expect(
      cookieHeaderFingerprint(header),
      isNot(cookieHeaderFingerprint('userinfo=other; csrf=token')),
    );
  });
}
