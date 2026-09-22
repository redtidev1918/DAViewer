import 'package:daviewer/app/app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop scroll behavior allows mouse and trackpad drags', () {
    const behavior = AppScrollBehavior();

    expect(
      behavior.dragDevices,
      containsAll(<PointerDeviceKind>{
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.touch,
      }),
    );
  });
}
