import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/library.dart';

void main() {
  testWidgets('returning to the foreground refreshes the list on any tab', (t) async {
    var lists = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('papyr/native'), (c) async {
      if (c.method == 'list') lists++;
      return c.method == 'list' ? <Object?>[] : null;
    });
    library; // no FilesScreen mounted
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused,
        AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pump();
    expect(lists, 1);
  });
}
