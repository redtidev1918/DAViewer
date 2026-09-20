import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/history/visit_history_store.dart';

/// Local visit history is cheap to load from disk and must refresh whenever a
/// detail screen records a new visit.
final visitHistoryProvider = FutureProvider<List<ArtworkVisit>>(
  (_) => VisitHistoryStore.load(),
);
