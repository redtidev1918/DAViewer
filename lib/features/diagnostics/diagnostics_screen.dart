import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/diagnostics/app_logger.dart';
import '../../core/diagnostics/crash_marker.dart';
import '../../core/diagnostics/report_builder.dart';
import '../../core/diagnostics/log_redactor.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/updates/update_checker.dart';

/// Shows the current session's log tail and error summary, plus a
/// user-initiated, privacy-preserving bug report.
final class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

final class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  String _logTail = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  Future<void> _loadLog() async {
    setState(() => _loading = true);
    final s = strings(ref.read(appLanguageProvider));
    try {
      final dir = Directory(AppLogger.instance.logsDirectory);
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.log'))
          .cast<File>()
          .toList()
          .then((list) => list..sort((a, b) => b.path.compareTo(a.path)));
      final target = files.isEmpty ? null : files.first;
      if (target == null) {
        setState(() {
          _logTail = s.noLogFile;
          _loading = false;
        });
        return;
      }
      final lines = await target.readAsLines();
      final tail = lines.length <= 120
          ? lines
          : lines.sublist(lines.length - 120);
      setState(() {
        _logTail = tail.join('\n');
        _loading = false;
      });
    } on Object catch (error) {
      setState(() {
        _logTail = s.logReadFailed(error);
        _loading = false;
      });
    }
  }

  Future<void> _reportProblem(AppStrings s) async {
    var includeLog = false;
    final names = <String>[
      ref.read(authControllerProvider).account?.username ?? '',
      ref.read(webSessionControllerProvider).username,
    ];
    final excerpt = LogRedactor.redactAll(_logTail, accountNames: names);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          title: Text(s.reportPreviewTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(s.reportPreviewBody),
              const SizedBox(height: 12),
              Text(
                'DAViewer v$appVersion · ${ReportBuilder.currentPlatform()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeLog,
                onChanged: (value) =>
                    setState(() => includeLog = value ?? false),
                title: Text(s.includeLog),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (includeLog)
                SizedBox(
                  height: 180,
                  child: SingleChildScrollView(child: SelectableText(excerpt)),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.openReport),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final url = ReportBuilder.issueUrl(
      version: appVersion,
      platform: ReportBuilder.currentPlatform(),
      logExcerpt: includeLog ? excerpt : null,
    );
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final logger = AppLogger.instance;
    final s = strings(ref.watch(appLanguageProvider));
    final crashedLastSession = ref.watch(crashDetectedProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.diagnostics),
        actions: <Widget>[
          IconButton(
            tooltip: s.reportProblem,
            onPressed: () => _reportProblem(s),
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            tooltip: s.refresh,
            onPressed: _loadLog,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (crashedLastSession)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.crashDetectedHint,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Icon(
                  logger.errorCount == 0
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: logger.errorCount == 0
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  logger.errorCount == 0
                      ? s.noErrorsThisRun
                      : s.errorsThisRun(logger.errorCount),
                ),
                const Spacer(),
                Text(
                  s.logDirectory(logger.logsDisplayName),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SelectableText(
                    _logTail,
                    style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
                  ),
          ),
        ],
      ),
    );
  }
}
