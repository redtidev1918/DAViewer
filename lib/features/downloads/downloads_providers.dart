import 'dart:async';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/runtime/runtime_provider.dart';

/// Live download state backed by one initial database read plus incremental
/// transfer snapshots. Progress events update the matching row directly instead
/// of re-reading the whole native database on every byte/progress callback.
final class DownloadsController extends StateNotifier<DownloadsState> {
  DownloadsController(this._manager) : super(const DownloadsState.loading()) {
    _subscription = _manager.updates.listen(
      _applyUpdate,
      onError: _applyStreamError,
    );
    unawaited(_reload());
  }

  final TransferManager _manager;
  late final StreamSubscription<TransferSnapshot> _subscription;
  final Map<String, TransferSnapshot> _liveUpdates =
      <String, TransferSnapshot>{};
  final Map<String, int> _liveSequences = <String, int>{};
  int _eventSequence = 0;

  void _applyUpdate(TransferSnapshot snapshot) {
    if (!mounted) return;
    _eventSequence++;
    _liveUpdates[snapshot.id] = snapshot;
    _liveSequences[snapshot.id] = _eventSequence;
    final items = List<TransferSnapshot>.of(state.items);
    final index = items.indexWhere((item) => item.id == snapshot.id);
    if (index < 0) {
      items.insert(0, snapshot);
    } else {
      items[index] = snapshot;
    }
    state = DownloadsState.data(items, isDeleting: state.isDeleting);
  }

  void _applyStreamError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    state = DownloadsState.data(
      state.items,
      isDeleting: state.isDeleting,
      error: error,
    );
  }

  Future<void> _reload() async {
    final startedAtSequence = _eventSequence;
    try {
      await _manager.initialize();
      final records = await _manager.records();
      if (!mounted) return;
      // A progress event may have arrived while records() was in flight. Merge
      // only events newer than this read; older in-memory rows must not mask a
      // genuinely newer database state during manual refresh/resume.
      final merged = records
          .map(
            (record) => (_liveSequences[record.id] ?? 0) > startedAtSequence
                ? _liveUpdates[record.id]!
                : record,
          )
          .toList();
      final mergedIds = merged.map((item) => item.id).toSet();
      for (final entry in _liveUpdates.entries) {
        if ((_liveSequences[entry.key] ?? 0) > startedAtSequence &&
            mergedIds.add(entry.key)) {
          merged.insert(0, entry.value);
        }
      }
      state = DownloadsState.data(merged, isDeleting: state.isDeleting);
    } on Object catch (error) {
      if (!mounted) return;
      state = DownloadsState.data(
        state.items,
        isDeleting: state.isDeleting,
        error: error,
      );
    }
  }

  Future<void> refresh() => _reload();

  /// Permanently removes all finished transfers and their known local files.
  /// Always reloads afterward so a partial failure remains visible and can be
  /// retried instead of leaving the UI out of sync with persisted records.
  Future<void> deleteFinished() async {
    if (state.isDeleting) return;
    state = DownloadsState.data(state.items, isDeleting: true);
    try {
      final records = await _manager.records();
      for (final record in records) {
        if (record.isFinal) await _manager.remove(record.id);
      }
    } finally {
      await _reload();
      if (mounted) {
        state = DownloadsState.data(
          state.items,
          error: state.error,
          isDeleting: false,
        );
      }
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

final class DownloadsState {
  const DownloadsState.loading()
    : items = const <TransferSnapshot>[],
      isLoading = true,
      isDeleting = false,
      error = null;

  const DownloadsState.data(this.items, {this.isDeleting = false, this.error})
    : isLoading = false;

  final List<TransferSnapshot> items;
  final bool isLoading;
  final bool isDeleting;
  final Object? error;
}

final downloadsProvider =
    StateNotifierProvider<DownloadsController, DownloadsState>(
      (ref) => DownloadsController(ref.read(runtimeProvider).transfers),
    );
