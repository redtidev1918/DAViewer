import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/web_session.dart';

/// A value-safe summary of deviantart.com cookies for lifecycle diagnostics.
/// Raw Cookie values, full CSRF tokens, and full Cookie headers are never
/// logged; only a SHA-256 fingerprint plus structural metadata is recorded.
final class WebSessionCookieSnapshot {
  const WebSessionCookieSnapshot({
    required this.source,
    required this.count,
    required this.names,
    required this.domains,
    required this.withExpiry,
    required this.sessionOnlyCount,
    required this.secureCount,
    required this.httpOnlyCount,
    required this.fingerprint,
  });

  final String source;
  final int count;
  final List<String> names;
  final Set<String> domains;
  final int withExpiry;
  final int sessionOnlyCount;
  final int secureCount;
  final int httpOnlyCount;
  final String fingerprint;

  String logLine() =>
      'cookie snapshot source=$source count=$count '
      'names=[${names.join(',')}] domains=[${domains.join(',')}] '
      'expiry=$withExpiry sessionOnly=$sessionOnlyCount '
      'secure=$secureCount httpOnly=$httpOnlyCount '
      'fingerprint=$fingerprint';
}

WebSessionCookieSnapshot cookieSnapshot({
  required String source,
  required List<Cookie> cookies,
}) {
  final names = <String>[];
  final domains = <String>{};
  var withExpiry = 0;
  var sessionOnlyCount = 0;
  var secureCount = 0;
  var httpOnlyCount = 0;
  for (final cookie in cookies) {
    names.add(cookie.name);
    final domain = cookie.domain;
    if (domain != null && domain.isNotEmpty) domains.add(domain);
    if (cookie.expiresDate != null) withExpiry += 1;
    if (cookie.isSessionOnly == true) sessionOnlyCount += 1;
    if (cookie.isSecure == true) secureCount += 1;
    if (cookie.isHttpOnly == true) httpOnlyCount += 1;
  }
  names.sort();
  return WebSessionCookieSnapshot(
    source: source,
    count: cookies.length,
    names: names,
    domains: domains,
    withExpiry: withExpiry,
    sessionOnlyCount: sessionOnlyCount,
    secureCount: secureCount,
    httpOnlyCount: httpOnlyCount,
    fingerprint: webSessionFingerprint(cookies),
  );
}

String webSessionFingerprint(List<Cookie> cookies) {
  final lines = <String>[];
  for (final cookie
      in cookies.toList()..sort(
        (a, b) => '${a.name}|${a.domain}|${a.path}'.compareTo(
          '${b.name}|${b.domain}|${b.path}',
        ),
      )) {
    lines.add(
      '${cookie.name}|${cookie.domain}|${cookie.path}|${cookie.value}|'
      '${cookie.isSecure}|${cookie.isHttpOnly}|'
      '${cookie.isSessionOnly}|${cookie.expiresDate ?? ''}',
    );
  }
  return sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

String webSessionMapFingerprint(Map<String, String> cookies) {
  final keys = cookies.keys.toList()..sort();
  final lines = keys.map((key) => '$key=${cookies[key]}');
  return sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

/// Fingerprint for the structured persisted cookie list, so a snapshot with
/// the same names/values but different domains, paths, or expiry is never
/// treated as unchanged.
String webSessionPersistedFingerprint(List<PersistedWebCookie> cookies) {
  final sorted = cookies.toList()
    ..sort(
      (a, b) => '${a.name}|${a.domain}|${a.path}'.compareTo(
        '${b.name}|${b.domain}|${b.path}',
      ),
    );
  final lines = sorted.map(
    (cookie) =>
        '${cookie.name}|${cookie.domain}|${cookie.path}|${cookie.value}|'
        '${cookie.isSecure}|${cookie.isHttpOnly}|${cookie.isSessionOnly}|'
        '${cookie.expiresDate ?? ''}',
  );
  return sha256.convert(utf8.encode(lines.join('\n'))).toString();
}

int cookieHeaderCount(String header) {
  if (header.trim().isEmpty) return 0;
  return header
      .split(';')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .length;
}

String cookieHeaderFingerprint(String header) =>
    sha256.convert(utf8.encode(header)).toString();
