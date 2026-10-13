import 'dart:async';
import 'dart:convert';

import 'web_session_verifier.dart';

/// Both browser hosts evaluate this script themselves. No identity from a
/// cookie or an untrusted JS bridge payload is allowed to confirm a session.
const browserSessionEvidenceScript = '''
(function() {
  var state = window.__INITIAL_STATE__ || {};
  // DeviantArt renders the session under the redux-style key `@@publicSession`
  // (verified against the production home page); the single-@ spelling is only
  // a legacy tolerance.
  var session = state['@@publicSession'] || state['@publicSession'] || {};
  var user = session.user || {};
  var text = document.body ? document.body.innerText : '';
  return JSON.stringify({
    csrf: typeof window.__CSRF_TOKEN__ === 'string' ? window.__CSRF_TOKEN__ : '',
    username: typeof user.username === 'string' ? user.username : null,
    loggedIn: typeof session.isLoggedIn === 'boolean' ? session.isLoggedIn : null,
    initialized: !!(state['@@publicSession'] || state['@publicSession']),
    blocked: text.indexOf('Max challenge attempts exceeded') >= 0,
    challenge: !!document.querySelector('#px-captcha, #challenge-container'),
    origin: location.origin
  });
})()
''';

final class BrowserSessionEvidence {
  const BrowserSessionEvidence({
    this.username,
    this.loggedIn,
    this.csrf = '',
    this.initialized = false,
    this.blocked = false,
    this.challenge = false,
    this.parseFailed = false,
    this.identitySource = 'page_global',
  });

  final String? username;

  /// The page's own `isLoggedIn` statement. `null` means the page did not
  /// render the flag; `false` is an explicit server-signed-out answer.
  final bool? loggedIn;
  final String csrf;
  final bool initialized;
  final bool blocked;
  final bool challenge;
  final bool parseFailed;
  final String identitySource;

  bool get hasIdentity => username != null && username!.isNotEmpty;
  String get classification => blocked
      ? 'blocked'
      : challenge
      ? 'challenge'
      : parseFailed
      ? 'parse_failed'
      : loggedIn == false || username == 'anonymous'
      ? 'explicit_anonymous'
      : hasIdentity
      ? 'verified_identity'
      : initialized
      ? 'identity_pending'
      : 'page_uninitialized';

  static BrowserSessionEvidence decode(Object? raw) {
    try {
      if (raw is! String) {
        return const BrowserSessionEvidence(parseFailed: true);
      }
      final data = jsonDecode(raw);
      if (data is! Map || data['origin'] != 'https://www.deviantart.com') {
        return const BrowserSessionEvidence(parseFailed: true);
      }
      return BrowserSessionEvidence(
        username: (data['username'] as String?)?.trim(),
        loggedIn: data['loggedIn'] is bool ? data['loggedIn'] as bool? : null,
        csrf: data['csrf'] as String? ?? '',
        initialized: data['initialized'] == true,
        blocked: data['blocked'] == true,
        challenge: data['challenge'] == true,
      );
    } on Object {
      return const BrowserSessionEvidence(parseFailed: true);
    }
  }
}

/// Some rendered pages keep the server's initializer script after removing the
/// global during hydration. Read only the current trusted document; Cookie,
/// OAuth identity, CSRF and public profile markup cannot supply this evidence.
Future<BrowserSessionEvidence> readBrowserSessionEvidence({
  required Future<Uri?> Function() getUrl,
  required Future<Object?> Function() evaluate,
  required Future<String?> Function() getHtml,
}) async {
  final before = await getUrl();
  if (before?.scheme != 'https' || before?.host != 'www.deviantart.com') {
    return const BrowserSessionEvidence();
  }
  final page = BrowserSessionEvidence.decode(await evaluate());
  if (page.hasIdentity || page.blocked || page.challenge || page.csrf.isEmpty) {
    return page;
  }
  String? html;
  try {
    html = await getHtml();
  } on Object {
    return page;
  }
  if (await getUrl() != before) return const BrowserSessionEvidence();
  final username = html == null
      ? null
      : WebSessionVerifier.pageUsernameFromInitialState(html);
  if (username == null || username.isEmpty) return page;
  return BrowserSessionEvidence(
    username: username,
    csrf: page.csrf,
    initialized: true,
    identitySource: 'document_initial_state',
  );
}

/// One bounded observation window spanning load stops, redirects and SPA
/// history updates. Events wake the same sampler; they never grant a verdict.
/// Navigation invalidates reads already in progress. Only one read runs at once.
final class BrowserSessionObserver {
  BrowserSessionObserver({
    required this.read,
    required this.onEvidence,
    required this.onDeadline,
    this.budget = const Duration(seconds: 20),
    this.interval = const Duration(milliseconds: 500),
  });

  final Future<BrowserSessionEvidence> Function() read;
  final void Function(BrowserSessionEvidence) onEvidence;
  final void Function() onDeadline;
  final Duration budget;
  final Duration interval;
  Timer? _deadline;
  Timer? _sampleTimer;
  bool _disposed = false;
  bool _reading = false;
  bool _loading = false;
  int _navigation = 0;
  String? _lastEvidence;
  bool get isDisposed => _disposed;

  /// Visible hosts may start a fresh bounded window after a real navigation
  /// or user reload; headless hosts retain their original transaction deadline.
  void restart() {
    dispose();
    _disposed = false;
    start();
  }

  void start() {
    if (_disposed || _deadline != null) return;
    _deadline = Timer(budget, () {
      dispose();
      onDeadline();
    });
    _sampleTimer = Timer.periodic(interval, (_) => unawaited(sample()));
    unawaited(sample());
  }

  void navigationStarted({bool loading = false}) {
    _navigation++;
    if (loading) _loading = true;
    _lastEvidence = null;
  }

  /// A full navigation may still expose the previous document while loading.
  /// SPA history updates invalidate reads without pausing asynchronous sampling.
  void navigationCommitted() {
    _loading = false;
    _navigation++;
    _lastEvidence = null;
  }

  Future<void> sample() async {
    if (_disposed || _reading || _loading) return;
    _reading = true;
    final navigation = _navigation;
    try {
      BrowserSessionEvidence evidence;
      try {
        evidence = await read();
      } on Object {
        evidence = const BrowserSessionEvidence(parseFailed: true);
      }
      if (_disposed || navigation != _navigation) return;
      // Token rotation must still reach the consumer without logging its value.
      final key =
          '${evidence.classification}:${evidence.username}:${evidence.csrf}';
      if (_lastEvidence == key) return;
      _lastEvidence = key;
      onEvidence(evidence);
    } finally {
      _reading = false;
    }
  }

  void dispose() {
    _disposed = true;
    _navigation++;
    _deadline?.cancel();
    _sampleTimer?.cancel();
    _deadline = null;
    _sampleTimer = null;
    _lastEvidence = null;
  }
}
