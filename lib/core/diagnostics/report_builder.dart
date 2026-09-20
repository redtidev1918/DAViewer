import 'dart:io';

import 'log_redactor.dart';

/// Builds a pre-filled GitHub issue URL for a user-initiated bug report. The
/// body contains only non-identifying facts: app version, platform, and an
/// optional redacted log excerpt. Nothing is sent automatically — the URL opens
/// in the user's own browser, where they review and submit it themselves.
final class ReportBuilder {
  const ReportBuilder._();

  static const String _base =
      'https://github.com/redtidev1918/DAViewer/issues/new';

  static String issueUrl({
    required String version,
    required String platform,
    String? logExcerpt,
  }) {
    final body = StringBuffer()
      ..writeln('## Description')
      ..writeln('<!-- Describe what happened and how to reproduce it. -->')
      ..writeln()
      ..writeln('## Environment')
      ..writeln('- App version: $version')
      ..writeln('- Platform: $platform');
    if (logExcerpt != null && logExcerpt.trim().isNotEmpty) {
      body
        ..writeln()
        ..writeln('## Log excerpt (redacted)')
        ..writeln('```')
        ..writeln(LogRedactor.redactAll(logExcerpt))
        ..writeln('```');
    }
    final title = Uri.encodeQueryComponent('[Bug] ');
    return '$_base?title=$title&body=${Uri.encodeComponent(body.toString())}';
  }

  static String currentPlatform() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }
}
