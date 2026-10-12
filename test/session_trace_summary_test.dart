import 'package:daviewer/core/diagnostics/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../scripts/summarize-session-recovery.dart';

void main() {
  test('IDs are scoped per launch and incomplete/duplicate terminal facts stay visible', () {
    const fixture = '''DAViewer diagnostic archive; sessions=2
=== launch a.log ===
[app] buildRevision=synthetic
[home] rfy requestId=rfy-1 phase=in_flight transportId=rfy-1-t1
[home] rfy requestId=rfy-1 phase=accepted
[home] rfy requestId=rfy-1 phase=completed
=== launch b.log ===
[home] rfy requestId=rfy-1 phase=created
[home] rfy requestId=rfy-2 phase=discarded discardReason=account_changed
[home] rfy requestId=rfy-2 phase=failed
''';
    final result = summarizeSessionTrace(fixture);
    final launches = result['launches'] as List<Map<String, Object?>>;
    expect(launches, hasLength(2));
    final first = (launches[0]['requests'] as Map)['rfy-1'] as Map;
    final second = launches[1]['requests'] as Map;
    expect(first['physicalTransportCount'], 1);
    expect(first['missingTerminal'], isFalse);
    expect((second['rfy-1'] as Map)['missingTerminal'], isTrue);
    expect((second['rfy-2'] as Map)['multipleTerminals'], isTrue);
    expect(result['deviceAcceptance'], startsWith('PENDING'));
  });
  test('previous-account free-form logs are redacted without knowing current account', () {
    final text = LogRedactor.redactAll(
      'web session candidate: old-private-name\nuser=old-private-name\ncode=secret-value',
    );
    expect(text, isNot(contains('old-private-name')));
    expect(text, isNot(contains('secret-value')));
  });
}
