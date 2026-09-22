import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../auth/web_session_diagnostics.dart';

/// A deviantart.com cookie preserved with the metadata the WebView store needs
/// to restore it faithfully (domain/path/expiry/security flags). Persisting a
/// plain name→value map drops that metadata and collapses same-name cookies
/// from different domains or paths, which is why a restored session could lose
/// auth cookies and force a re-login after an update.
final class PersistedWebCookie {
  const PersistedWebCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path = '/',
    this.expiresDate,
    this.isSecure = false,
    this.isHttpOnly = false,
    this.isSessionOnly = false,
  });

  factory PersistedWebCookie.fromBrowserCookie(Cookie cookie) =>
      PersistedWebCookie(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: (cookie.path?.isNotEmpty ?? false) ? cookie.path! : '/',
        expiresDate: cookie.expiresDate == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!),
        isSecure: cookie.isSecure == true,
        isHttpOnly: cookie.isHttpOnly == true,
        isSessionOnly: cookie.isSessionOnly == true,
      );

  final String name;
  final String value;
  final String? domain;
  final String path;
  final DateTime? expiresDate;
  final bool isSecure;
  final bool isHttpOnly;
  final bool isSessionOnly;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
    if (domain != null && domain!.isNotEmpty) 'domain': domain,
    if (path.isNotEmpty && path != '/') 'path': path,
    if (expiresDate != null)
      'expiresDate': expiresDate!.toUtc().toIso8601String(),
    if (isSecure) 'secure': true,
    if (isHttpOnly) 'httpOnly': true,
    if (isSessionOnly) 'sessionOnly': true,
  };

  static PersistedWebCookie? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final cookieValue = value['value'];
    if (name is! String || name.isEmpty || cookieValue is! String) return null;
    DateTime? expiresDate;
    final rawExpiry = value['expiresDate'];
    if (rawExpiry is String && rawExpiry.isNotEmpty) {
      // [toJson] stores UTC; keep the instant as-is so the serialized value
      // round-trips exactly regardless of the local timezone.
      expiresDate = DateTime.tryParse(rawExpiry);
    }
    final rawPath = value['path'];
    return PersistedWebCookie(
      name: name,
      value: cookieValue,
      domain: value['domain'] is String ? value['domain'] as String : null,
      path: rawPath is String && rawPath.isNotEmpty ? rawPath : '/',
      expiresDate: expiresDate,
      isSecure: value['secure'] == true,
      isHttpOnly: value['httpOnly'] == true,
      isSessionOnly: value['sessionOnly'] == true,
    );
  }
}

/// Decodes a persisted `cookies` value into the structured list. The legacy
/// name→value map format (which dropped metadata) is migrated into host-only
/// cookies so an existing snapshot still restores after the upgrade.
List<PersistedWebCookie> parsePersistedCookies(Object? value) {
  if (value is List) {
    final cookies = <PersistedWebCookie>[];
    for (final item in value) {
      final cookie = PersistedWebCookie.fromJson(item);
      if (cookie != null) cookies.add(cookie);
    }
    return cookies;
  }
  if (value is Map) {
    return <PersistedWebCookie>[
      for (final entry in value.entries)
        if (entry.key is String &&
            entry.value is String &&
            (entry.key as String).isNotEmpty)
          PersistedWebCookie(
            name: entry.key as String,
            value: entry.value as String,
          ),
    ];
  }
  return const <PersistedWebCookie>[];
}

/// Reads deviantart.com cookies owned by the hidden public browser so
/// website-only metadata adapters can reuse its anonymous session.
///
/// The CSRF token is read from the browser page because some undocumented
/// endpoints reject a plain HTTP client even when the page is public.
/// One atomic WebView Cookie read. The username, Cookie list and fingerprint
/// always come from the same instant, so a successful identity can never be
/// paired with an empty Cookie snapshot from a later read.
final class WebSessionData {
  const WebSessionData({
    required this.cookies,
    required this.username,
    required this.fingerprint,
  });

  final List<PersistedWebCookie> cookies;
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
      final persisted = <PersistedWebCookie>[
        for (final cookie in cookies)
          PersistedWebCookie.fromBrowserCookie(cookie),
      ];
      return WebSessionData(
        cookies: persisted,
        username: WebSession.usernameFromCookies(persisted),
        fingerprint: webSessionFingerprint(cookies),
      );
    } on Object {
      return null;
    }
  }

  /// Reads the deviantart.com cookies with their storage metadata. Returns an
  /// empty list when the cookie manager is unavailable.
  Future<List<PersistedWebCookie>> cookies() async {
    try {
      final cookies = await _cookieManager().getCookies(
        url: WebUri(_home.toString()),
      );
      return <PersistedWebCookie>[
        for (final cookie in cookies)
          PersistedWebCookie.fromBrowserCookie(cookie),
      ];
    } on Object {
      // Same as [cookieHeader]: an early-startup failure is treated as empty.
      return const <PersistedWebCookie>[];
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
    return cookieHeaderFrom(await cookies());
  }

  /// Serializes an already-read Cookie list without a second CookieStore read.
  static String cookieHeaderFrom(List<PersistedWebCookie> cookies) =>
      cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');

  /// The signed-in username carried by the `userinfo` cookie, or `''`.
  static String usernameFromCookies(List<PersistedWebCookie> cookies) {
    for (final cookie in cookies) {
      if (cookie.name == 'userinfo') {
        final username = usernameFromUserInfo(cookie.value);
        if (username.isNotEmpty) return username;
      }
    }
    return '';
  }

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
