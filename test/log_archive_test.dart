import 'dart:io';

import 'package:daviewer/core/diagnostics/log_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one export includes ten separate cold starts in order and redacts credentials', () async {
    final directory = await Directory.systemTemp.createTemp(
      'daviewer-log-archive-',
    );
    addTearDown(() => directory.delete(recursive: true));
    for (var i = 0; i < 10; i++) {
      await File(
        '${directory.path}/daviewer-2026-10-12-${i.toString().padLeft(2, '0')}.log',
      ).writeAsString(
        'launch=$i recoveryId=recovery-1 username=artist csrf_token=SECRET Cookie: SECRET\n',
      );
    }
    final text = await LogArchive.readRecent(directory);
    expect(text, contains('sessions=10'));
    expect('=== launch'.allMatches(text), hasLength(10));
    expect(text.indexOf('launch=0'), lessThan(text.indexOf('launch=9')));
    expect(text, isNot(contains('SECRET')));
    expect(text, isNot(contains('username=artist')));
  });

  test(
    'archive bounds sessions and bytes with visible truncation evidence',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'daviewer-log-limits-',
      );
      addTearDown(() => directory.delete(recursive: true));
      for (var i = 0; i < 3; i++) {
        await File('${directory.path}/launch-$i.log').writeAsString('x' * 100);
      }
      final text = await LogArchive.readRecent(
        directory,
        maxSessions: 2,
        maxBytesPerSession: 10,
      );
      expect(text, contains('sessions=2'));
      expect(text, isNot(contains('launch-0.log')));
      expect('[truncated:'.allMatches(text), hasLength(2));
    },
  );
}
