import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path_provider/path_provider.dart';

/// Presentation evidence only. Never grants access or changes authentication.
enum LoginChannel { web, api }

enum LoginCheckResult {
  unknown,
  authenticated,
  unauthenticated,
  unavailable,
  challenge,
}

enum LoginStorageResult {
  unknown,
  saved,
  restoring,
  restored,
  notNeeded,
  failed,
}

final loginObservationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final loginHistoryStoreProvider = Provider<LoginHistoryStore>(
  (ref) => LoginHistoryStore(),
);
final loginObservationProvider =
    StateNotifierProvider.family<
      LoginObservationController,
      LoginObservation,
      LoginChannel
    >(
      (ref, channel) => LoginObservationController(
        channel,
        ref.read(loginHistoryStoreProvider),
        ref.read(loginObservationClockProvider),
      ),
    );

final class LoginObservation {
  const LoginObservation({
    this.owner = '',
    this.result = LoginCheckResult.unknown,
    this.checking = false,
    this.lastAttempt,
    this.lastSuccess,
    this.reason = '',
    this.save = LoginStorageResult.unknown,
    this.restore = LoginStorageResult.unknown,
    this.storageAt,
    this.storageReason = '',
  });
  final String owner;
  final LoginCheckResult result;
  final bool checking;
  final DateTime? lastAttempt;
  final DateTime? lastSuccess;
  final String reason;
  final LoginStorageResult save;
  final LoginStorageResult restore;
  final DateTime? storageAt;
  final String storageReason;

  LoginObservation copyWith({
    LoginCheckResult? result,
    bool? checking,
    DateTime? lastAttempt,
    DateTime? lastSuccess,
    String? reason,
    LoginStorageResult? save,
    LoginStorageResult? restore,
    DateTime? storageAt,
    String? storageReason,
  }) => LoginObservation(
    owner: owner,
    result: result ?? this.result,
    checking: checking ?? this.checking,
    lastAttempt: lastAttempt ?? this.lastAttempt,
    lastSuccess: lastSuccess ?? this.lastSuccess,
    reason: reason ?? this.reason,
    save: save ?? this.save,
    restore: restore ?? this.restore,
    storageAt: storageAt ?? this.storageAt,
    storageReason: storageReason ?? this.storageReason,
  );
}

/// Stores only a fixed allowlist of non-credential observations. Historical
/// success is never restored as a current authenticated verdict.
class LoginHistoryStore {
  LoginHistoryStore({this.directory});
  final Future<Directory> Function()? directory;
  Future<void> _tail = Future<void>.value();
  Future<File> _file(LoginChannel channel) async {
    final dir = await (directory?.call() ?? getApplicationSupportDirectory());
    return File('${dir.path}/login-history-${channel.name}.json');
  }

  Future<LoginObservation?> read(LoginChannel channel, String owner) async {
    try {
      await _tail;
      final file = await _file(channel);
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['owner'] != owner) return null;
      DateTime? date(String key) =>
          data[key] is String ? DateTime.tryParse(data[key]) : null;
      LoginStorageResult storage(String key) =>
          LoginStorageResult.values
              .where((value) => value.name == data[key])
              .firstOrNull ??
          LoginStorageResult.unknown;
      return LoginObservation(
        owner: owner,
        lastAttempt: date('attempt'),
        lastSuccess: date('success'),
        reason: _safeReason(data['reason']),
        save: storage('save'),
        restore: storage('restore'),
        storageAt: date('storageAt'),
        storageReason: _safeReason(data['storageReason']),
      );
    } on Object {
      return null;
    }
  }

  Future<void> write(LoginChannel channel, LoginObservation state) {
    final next = _tail.then((_) async {
      final file = await _file(channel);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'owner': state.owner,
          'attempt': state.lastAttempt?.toUtc().toIso8601String(),
          'success': state.lastSuccess?.toUtc().toIso8601String(),
          'reason': _safeReason(state.reason),
          'save': state.save.name,
          'restore': state.restore.name,
          'storageAt': state.storageAt?.toUtc().toIso8601String(),
          'storageReason': _safeReason(state.storageReason),
        }),
        flush: true,
      );
    });
    _tail = next.then((_) {}, onError: (Object _) {});
    return _tail;
  }

  /// Resolves once every queued write has settled. Production callers persist
  /// fire-and-forget; tests and graceful shutdown use this to avoid deleting
  /// a directory that still has an open history file (Windows errno 32).
  Future<void> flush() => _tail;
}

String _safeReason(Object? value) =>
    const <String>{
      'network',
      'timeout',
      'unavailable',
      'challenge',
      'unauthenticated',
      'read_failed',
      'write_failed',
      'missing_identity',
      'missing_snapshot',
      'partial_restore',
      'not_configured',
      'credentials_changed',
    }.contains(value)
    ? value as String
    : '';

final class LoginObservationController extends StateNotifier<LoginObservation> {
  LoginObservationController(this.channel, this.store, this.now)
    : super(const LoginObservation());
  final LoginChannel channel;
  final LoginHistoryStore store;
  final DateTime Function() now;
  int _epoch = 0;
  Future<void> _historyReady = Future<void>.value();

  void bind(String username) {
    final owner = username.trim().toLowerCase();
    if (owner == state.owner) return;
    final epoch = ++_epoch;
    state = LoginObservation(owner: owner);
    _historyReady = store.read(channel, owner).then((history) {
      if (!mounted || epoch != _epoch || history == null) return;
      state = state.copyWith(
        lastAttempt: state.lastAttempt ?? history.lastAttempt,
        lastSuccess: state.lastSuccess ?? history.lastSuccess,
        reason: state.lastAttempt == null ? history.reason : state.reason,
        save: state.storageAt == null ? history.save : state.save,
        restore: state.storageAt == null ? history.restore : state.restore,
        storageAt: state.storageAt ?? history.storageAt,
        storageReason: state.storageAt == null
            ? history.storageReason
            : state.storageReason,
      );
    });
  }

  void begin(String owner) {
    bind(owner);
    state = state.copyWith(checking: true, lastAttempt: now(), reason: '');
  }

  void finish(LoginCheckResult result, {String reason = ''}) {
    state = state.copyWith(
      checking: false,
      result: result,
      reason: reason,
      lastAttempt: state.lastAttempt ?? now(),
      lastSuccess: result == LoginCheckResult.authenticated ? now() : null,
    );
    _persist();
  }

  void storage({
    LoginStorageResult? save,
    LoginStorageResult? restore,
    String reason = '',
  }) {
    state = state.copyWith(
      save: save,
      restore: restore,
      storageAt: now(),
      storageReason: reason,
    );
    _persist();
  }

  void _persist() {
    final epoch = _epoch;
    unawaited(
      _historyReady.then((_) async {
        if (mounted && epoch == _epoch) await store.write(channel, state);
      }),
    );
  }

  void reset() {
    _epoch++;
    state = const LoginObservation();
    unawaited(store.write(channel, state));
  }
}
