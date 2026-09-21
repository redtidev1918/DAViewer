import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One reminder the shell may show. Persistent banners are deduplicated by
/// [id]; pages never decide on their own whether a banner is already visible.
final class AppNotice {
  const AppNotice({
    required this.id,
    required this.message,
    this.actionLabel,
    this.action,
  });

  final String id;
  final String message;
  final String? actionLabel;
  final void Function()? action;
}

final class AppNoticeState {
  const AppNoticeState({this.current});

  final AppNotice? current;
}

final appNoticeControllerProvider =
    StateNotifierProvider<AppNoticeController, AppNoticeState>(
      (ref) => AppNoticeController(),
    );

final class AppNoticeController extends StateNotifier<AppNoticeState> {
  AppNoticeController() : super(const AppNoticeState());

  void show(AppNotice notice) {
    if (state.current?.id == notice.id) return;
    state = AppNoticeState(current: notice);
  }

  void clear(String id) {
    if (state.current?.id == id) {
      state = const AppNoticeState();
    }
  }
}
