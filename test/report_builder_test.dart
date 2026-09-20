import 'package:daviewer/core/diagnostics/log_redactor.dart';
import 'package:daviewer/core/diagnostics/report_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts token query parameters', () {
    final line =
        'https://example.test/auth?token=SECRET123&foo=bar&csrf_token=CSRF';
    final redacted = LogRedactor.redact(line);

    expect(redacted, contains('token=[redacted]'));
    expect(redacted, contains('csrf_token=[redacted]'));
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
    expect(Uri.decodeComponent(url), contains('token=[redacted]'));
    expect(Uri.decodeComponent(url), isNot(contains('LEAKED')));
  });
}
