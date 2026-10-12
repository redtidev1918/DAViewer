import 'dart:convert';
import 'dart:io';

import '../lib/core/diagnostics/log_redactor.dart';

/// Facts only. Request IDs are local to each launch; neither an accepted
/// response nor a synthetic log establishes real phone/incident acceptance.
Map<String, Object?> summarizeSessionTrace(String text) {
  final launches = <Map<String, Object?>>[];
  Map<String, Object?>? launch;
  var requests = <String, Map<String, Object?>>{};
  void startLaunch(String name) {
    requests = {};
    launch = {
      'launch': name,
      'buildRevision': 'unknown',
      'requests': requests,
      'observations': <String>[],
    };
    launches.add(launch!);
  }

  for (final line in text.split('\n')) {
    final section = RegExp(r'^=== launch (.*?) ===\s*$').firstMatch(line);
    if (section != null) {
      startLaunch(section[1]!);
      continue;
    }
    if (line.trim().isEmpty || line.startsWith('DAViewer diagnostic archive'))
      continue;
    if (launch == null) startLaunch('unsectioned');
    final fields = <String, String>{
      for (final match in RegExp(r'\b(\w+)=([^\s]+)').allMatches(line))
        match[1]!: match[2]!,
    };
    if (fields['buildRevision'] != null)
      launch!['buildRevision'] = fields['buildRevision'];
    if (line.contains('recovery ') ||
        line.contains('browser ') ||
        line.contains('oauthBridge') ||
        line.contains('login screen ') ||
        line.contains('oauth.callback.') ||
        line.contains('oauth.token.') ||
        line.contains('account loaded:')) {
      (launch!['observations'] as List<String>).add(line);
    }
    final id = fields['requestId'];
    if (id == null || !line.contains('[home]')) continue;
    final request = requests.putIfAbsent(
      id,
      () => {
        'phases': <String>[],
        'transports': <String>{},
        'events': <Map<String, String>>[],
      },
    );
    (request['events'] as List<Map<String, String>>).add(fields);
    if (fields['phase'] != null)
      (request['phases'] as List<String>).add(fields['phase']!);
    if (fields['transportId'] != null)
      (request['transports'] as Set<String>).add(fields['transportId']!);
  }
  for (final launch in launches) {
    for (final request
        in (launch['requests'] as Map<String, Map<String, Object?>>).values) {
      final phases = request['phases'] as List<String>;
      final terminals = phases
          .where((p) => ['accepted', 'discarded', 'failed'].contains(p))
          .toList();
      request['terminalPhases'] = terminals;
      request['missingTerminal'] = terminals.isEmpty;
      request['multipleTerminals'] = terminals.length > 1;
      request['completed'] = phases.contains('completed');
      final transports = (request['transports'] as Set<String>).toList();
      request['transports'] = transports;
      request['physicalTransportCount'] = transports.length;
    }
  }
  return {
    'deviceAcceptance': 'PENDING/manual evidence review',
    'launches': launches,
  };
}

Future<void> main(List<String> arguments) async {
  final options = <String, String>{};
  for (var index = 0; index + 1 < arguments.length; index += 2) {
    options[arguments[index]] = arguments[index + 1];
  }
  final input = options['--input'];
  final output = options['--output'];
  if (input == null || output == null || arguments.length != 4) {
    stderr.writeln(
      'Usage: dart run scripts/summarize-session-recovery.dart --input archive.txt --output new-directory',
    );
    exitCode = 64;
    return;
  }
  final directory = Directory(output).absolute;
  if (await directory.exists()) {
    stderr.writeln(
      'Choose a new output directory; existing evidence is never overwritten.',
    );
    exitCode = 73;
    return;
  }
  final text = LogRedactor.redactAll(await File(input).readAsString());
  final summary = summarizeSessionTrace(text);
  await directory.create(recursive: true);
  await File('${directory.path}/sanitized.txt').writeAsString(text);
  await File('${directory.path}/summary.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(summary));
  stdout.writeln(
    'Evidence organized in ${directory.path}; phone/incident acceptance requires manual review.',
  );
}
