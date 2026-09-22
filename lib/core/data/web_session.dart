import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../auth/web_session_diagnostics.dart';

/// Reads deviantart.com cookies owned by the hidden public browser so
/// website-only metadata adapters can reuse its anonymous session.
///
/// The CSRF token is read from the browser page because some undocumented
/// endpoints reject a plain HTTP client even when the page is public.
/// One atomic WebView Cookie read. The username, Cookie map and fingerprint
/// always come from the same instant, so a successful identity can never be
/// paired with an empty Cookie snapshot from a later read.
final class WebSessionData {
  const WebSessionData({
    required this.cookies,
    required this.username,
    required this.fingerprint,
  });

  final Map<String, String> cookies;
  final String username;
  final String fingerprint;
}

final class WebSession {
  const WebSession(this._cookieManager);

  final CookieManager Function() _cookieManager;

  static final Uri _home = Uri.parse('https://www.deviantart.com/');

  /// Makes one CookieManager read and derives the signed-in identity from it.
  /// Returns null only when the Cookie store itself is unavailable; an empty
  /// result is a valid anonymous read, not an unknown state.
  Future<WebSessionData?> readData() async {
    try {
      final cookies = await _cookieManager().getCookies(
        url: WebUri(_home.toString()),
      );
      final map = <String, String>{
        for (final cookie in cookies) cookie.name: cookie.value,
      };
      return WebSessionData(
        cookies: map,
        username: WebSession.usernameFromUserInfo(map['userinfo']),
        fingerprint: webSessionFingerprint(cookies),
      );
    } on Object {
      return null;
    }
  }

  /// Reads the deviantart.com cookies as a name → value map. Returns an empty
  /// map when the cookie manager is unavailable.
  Future<Map<String, String>> cookies() async {
    try {
      final cookies = await _cookieManager().getCookies(
        url: WebUri(_home.toString()),
      );
      return <String, String>{
        for (final cookie in cookies) cookie.name: cookie.value,
      };
    } on Object {
      // Same as [cookieHeader]: an early-startup failure is treated as empty.
      return const <String, String>{};
    }
  }

  /// Reads structural Cookie metadata for lifecycle diagnostics. Never logs
  /// values; fingerprints are SHA-256 of sorted name/domain/path/value fields.
  Future<WebSessionCookieSnapshot> snapshot({required String source}) async {
    try {
      final cookies = await _cookieManager().getCookies(
        url: WebUri(_home.toString()),
      );
      return cookieSnapshot(source: source, cookies: cookies);
    } on Object {
      return WebSessionCookieSnapshot(
        source: source,
        count: 0,
        names: const <String>[],
        domains: const <String>{},
        withExpiry: 0,
        sessionOnlyCount: 0,
        secureCount: 0,
        httpOnlyCount: 0,
        fingerprint: 'unavailable',
      );
    }
  }

  /// Serializes the deviantart.com cookies into a `Cookie` header value.
  Future<String> cookieHeader() async {
    // The cookie manager can be unavailable very early in startup; an empty
    // header simply makes the feed report an auth error, which the UI maps
    // to a sign-in prompt rather than a crash.
    final values = await cookies();
    return values.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Serializes an already-read Cookie map without a second CookieStore read.
  static String cookieHeaderFrom(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Extracts the signed-in username from a DeviantArt `userinfo` cookie
  /// value, or `''` when the cookie is absent, anonymous, or unparseable.
  static String usernameFromUserInfo(Object? value) {
    if (value is! String || value.isEmpty) return '';
    try {
      final decoded = Uri.decodeComponent(value);
      final jsonPart = decoded.split(';').last;
      final data = jsonDecode(jsonPart);
      if (data is Map && data['username'] is String) {
        return (data['username'] as String).trim();
      }
    } on Object {
      // Best effort; treat as anonymous.
    }
    return '';
  }
}

/// Pretty-prints cookies as indented JSON for export and clipboard copy. The
/// output round-trips through [parseImportedCookies].
String formatCookieExport(Map<String, String> cookies) =>
    const JsonEncoder.withIndent('  ').convert(cookies);

/// Parses user-pasted cookies for import. Accepts the JSON map produced by
/// [formatCookieExport], a browser-extension JSON array of cookie objects
/// (entries whose `domain` is not DeviantArt are ignored), or a
/// `name=value; name=value` Cookie header. Returns null when nothing
/// recognizable is found.
Map<String, String>? parseImportedCookies(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return <String, String>{
          for (final entry in decoded.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
        };
      }
      if (decoded is List) {
        final cookies = <String, String>{};
        for (final item in decoded) {
          if (item is! Map) continue;
          final domain = item['domain'];
          if (domain is String &&
              domain.isNotEmpty &&
              !domain.contains('deviantart.com')) {
            continue;
          }
          final name = item['name'];
          final value = item['value'];
          if (name is String && name.isNotEmpty && value is String) {
            cookies[name] = value;
          }
        }
        return cookies.isEmpty ? null : cookies;
      }
    } on Object {
      return null;
    }
    return null;
  }
  // Cookie header form: name=value; name=value.
  final cookies = <String, String>{};
  for (final pair in trimmed.split(';')) {
    final eq = pair.indexOf('=');
    if (eq <= 0) continue;
    final name = pair.substring(0, eq).trim();
    if (name.isEmpty) continue;
    cookies[name] = pair.substring(eq + 1).trim();
  }
  return cookies.isEmpty ? null : cookies;
}
