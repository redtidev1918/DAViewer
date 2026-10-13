import 'package:daviewer/core/diagnostics/log_redactor.dart';
import 'package:daviewer/core/diagnostics/report_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts IPv6 without losing timestamps or app versions', () {
    final result = LogRedactor.redact(
      '12:34:56 v0.5.10 [::1]:7890 2001:db8::123',
    );
    expect(result, contains('12:34:56 v0.5.10'));
    expect(result, isNot(contains('::1')));
    expect(result, isNot(contains('2001:db8')));
  });
  test('redacts identity, proxy IPs and user directory names', () {
    final redacted = LogRedactor.redactAll(
      'account loaded: Artist\nclaimed=Other server=Third username=Fourth\n'
      r'proxy 192.168.1.12:7890 file C:\Users\Private Name\app.log'
      '\n/Users/Someone/app.log /home/Person/app.log',
      accountNames: ['Artist'],
    );
    for (final private in [
      'Artist',
      'Other',
      'Third',
      'Fourth',
      '192.168.1.12',
      'Private Name',
      'Someone',
      'Person',
    ]) {
      expect(redacted, isNot(contains(private)));
    }
    expect(redacted, contains('app.log'));
    expect(redacted, contains(':7890'));
  });
  test('redacts token query parameters', () {
    final line =
        'https://example.test/auth?token=SECRET123&foo=bar&csrf_token=CSRF';
    final redacted = LogRedactor.redact(line);

    expect(redacted, contains('token=<redacted>'));
    expect(redacted, contains('csrf_token=<redacted>'));
    expect(redacted, isNot(contains('SECRET123')));
    expect(redacted, isNot(contains('=CSRF')));
    expect(redacted, contains('foo=bar'));
  });

  test('redacts cookie and authorization headers', () {
    expect(
      LogRedactor.redact('Cookie: userinfo=somevalue; session=abc'),
      'Cookie: [redacted]',
    );
    expect(
      LogRedactor.redact('Authorization: Bearer abc.def.ghi'),
      'Authorization: [redacted]',
    );
  });

  test('exported reports redact nested OAuth redirect parameters', () {
    const nested =
        'https://example.test/join?referer=https%3A%2F%2Fexample.test%2Fauth'
        '%3Fstate%3DONE_TIME_NONCE%26code%3DAUTH_CODE%26scope%3Dbasic';
    final redacted = LogRedactor.redactAll('load stop: $nested');
    expect(redacted, isNot(contains('ONE_TIME_NONCE')));
    expect(redacted, isNot(contains('AUTH_CODE')));
    expect(redacted, contains('scope%3Dbasic'));
    final report = Uri.decodeComponent(
      ReportBuilder.issueUrl(
        version: '0.5.13',
        platform: 'Android',
        logExcerpt: nested,
      ),
    );
    expect(report, isNot(contains('ONE_TIME_NONCE')));
    expect(report, isNot(contains('AUTH_CODE')));
  });

  test('redacts email addresses', () {
    expect(
      LogRedactor.redact('contact me@example.com please'),
      isNot(contains('me@example.com')),
    );
  });

  test('builds a pre-filled issue URL with redacted log', () {
    final url = ReportBuilder.issueUrl(
      version: '0.2.144',
      platform: 'macOS',
      logExcerpt: 'error | token=LEAKED',
    );

    expect(url, contains('github.com/redtidev1918/DAViewer/issues/new'));
    expect(Uri.decodeComponent(url), contains('App version: 0.2.144'));
    expect(Uri.decodeComponent(url), contains('Platform: macOS'));
    expect(Uri.decodeComponent(url), contains('token=<redacted>'));
    expect(Uri.decodeComponent(url), isNot(contains('LEAKED')));
  });
}
