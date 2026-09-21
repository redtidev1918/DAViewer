import 'package:daviewer/core/notice/app_notices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppNoticeController', () {
    test('deduplicates notices by id', () {
      final controller = AppNoticeController();
      const first = AppNotice(id: 'session', message: 'a');
      const second = AppNotice(id: 'session', message: 'b');
      const other = AppNotice(id: 'update', message: 'c');

      controller.show(first);
      controller.show(second);
      expect(controller.state.current?.id, 'session');
      expect(controller.state.current?.message, 'a');

      controller.show(other);
      expect(controller.state.current?.message, 'c');
    });

    test('clear removes only the matching notice', () {
      final controller = AppNoticeController();
      controller.show(const AppNotice(id: 'session', message: 'a'));
      controller.clear('other');
      expect(controller.state.current, isNotNull);
      controller.clear('session');
      expect(controller.state.current, isNull);
    });
  });
}
