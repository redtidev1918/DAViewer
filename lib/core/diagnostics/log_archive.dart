import 'dart:convert';
import 'dart:io';

import 'log_redactor.dart';

/// Cross-launch archive. Export at most twenty sessions and 512 KiB per
/// session, including a visible truncation marker. Never modifies source logs.
final class LogArchive {
  static Future<String> readRecent(
    Directory directory, {
    Iterable<String> accountNames = const [],
    int maxSessions = 20,
    int maxBytesPerSession = 512 * 1024,
  }) async {
    final files = await directory
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.log'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    final selected = files.take(maxSessions).toList().reversed;
    final result = StringBuffer(
      'DAViewer diagnostic archive; sessions=${selected.length}\n',
    );
    for (final file in selected) {
      final name = file.uri.pathSegments.last;
      result.writeln('\n=== launch $name ===');
      final handle = await file.open();
      try {
        final size = await handle.length();
        if (size > maxBytesPerSession) {
          result.writeln(
            '[truncated: last $maxBytesPerSession bytes of $size]',
          );
          await handle.setPosition(size - maxBytesPerSession);
        }
        final bytes = await handle.read(maxBytesPerSession);
        result.writeln(
          LogRedactor.redactAll(
            utf8.decode(bytes, allowMalformed: true),
            accountNames: accountNames,
          ),
        );
      } finally {
        await handle.close();
      }
    }
    return result.toString();
  }
}
