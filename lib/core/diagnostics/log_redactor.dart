import 'dart:io';

/// Removes credentials, tokens, and personally identifying fragments from a
/// diagnostic line before it is offered to the user for a bug report. This is a
/// conservative, best-effort redactor: it targets the obvious secrets and lets
/// ordinary log text through so a report stays useful.
final class LogRedactor {
  const LogRedactor._();

  static final List<RegExp> _patterns = <RegExp>[
    // OAuth / session parameters and their values, whether in a query string
    // (`?token=…`) or plain `key=value` text.
    RegExp(
      r'\b((?:access_token|refresh_token|id_token|csrf_token|client_secret|signature|sig|token|code|state)=)[^\s&,;]+',
      caseSensitive: false,
    ),
    // Header lines that carry credentials or a browser session.
    RegExp(r'(Cookie:\s*).*', caseSensitive: false),
    RegExp(r'(Authorization:\s*).*', caseSensitive: false),
    // Email addresses.
    RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'),
    RegExp(
      r'\b((?:\w*username|claimed|server|user)=)[^\s,;]+',
      caseSensitive: false,
    ),
    RegExp(r'(account loaded:\s*)[^\s,;]+', caseSensitive: false),
    RegExp(r'(web session candidate:\s*)[^\s,;]+', caseSensitive: false),
    RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
    RegExp(
      r'(?:[A-Za-z]:[\\/]Users[\\/]|/Users/|/home/)[^\\/\r\n]+',
      caseSensitive: false,
    ),
  ];

  static String redact(
    String line, {
    Iterable<String> accountNames = const [],
  }) {
    var result = line;
    for (final pattern in _patterns) {
      result = result.replaceAllMapped(
        pattern,
        (match) =>
            '${match.groupCount > 0 ? match.group(1) ?? '' : ''}[redacted]',
      );
    }
    result = result.replaceAllMapped(
      RegExp(
        r'(?<![\w:])(?:[0-9a-f]*:){2,}[0-9a-f:.]*(?![\w:])',
        caseSensitive: false,
      ),
      (match) => InternetAddress.tryParse(match[0]!) != null
          ? '[redacted]'
          : match[0]!,
    );
    for (final name in accountNames.where((name) => name.trim().isNotEmpty)) {
      result = result.replaceAll(
        RegExp(
          '(?<![\\w-])${RegExp.escape(name)}(?![\\w-])',
          caseSensitive: false,
        ),
        '[redacted]',
      );
    }
    return result;
  }

  static String redactAll(
    String text, {
    Iterable<String> accountNames = const [],
  }) => text
      .split('\n')
      .map((line) => redact(line, accountNames: accountNames))
      .join('\n');
}
