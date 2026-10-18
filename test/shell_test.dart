import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/main.dart';
import 'package:papyr/scan/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('papyr/native'), (c) async {
        calls.add(c);
        return null;
      });
  });

  Future<void> back(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) => TextButton(onPressed: () => goBack(c), child: const Text('voltar'))),
    ));
    await t.tap(find.text('voltar'));
    await t.pumpAndSettle();
  }

  testWidgets('Ajustes and empty Escanear go back to Arquivos', (t) async {
    for (final from in [2, 1]) {
      tab.value = from;
      session.clear();
      await back(t);
      expect(tab.value, 0);
    }
  });

  testWidgets('Escanear with photos asks; Cancelar keeps, Descartar clears', (t) async {
    tab.value = 1;
    session
      ..clear()
      ..add(Photo('/c/a.jpg'))
      ..add(Photo('/c/b.jpg'));
    await back(t);
    expect(find.text('Descartar 2 fotos?'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect((tab.value, session.photos.length), (1, 2));
    await back(t);
    await t.tap(find.text('Descartar'));
    await t.pumpAndSettle();
    expect((tab.value, session.photos.length), (0, 0));
    expect(calls.map((c) => c.method), contains('cleanCache'));
  });

  testWidgets('one photo is singular', (t) async {
    tab.value = 1;
    session
      ..clear()
      ..add(Photo('/c/a.jpg'));
    await back(t);
    expect(find.text('Descartar 1 foto?'), findsOneWidget);
  });

  // device check: after a live light/dark switch, 3-button nav kept the old theme's scrim and button color
  testWidgets('the shell turns off the system nav bar scrim in both themes', (t) async {
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    tab.value = 0;
    session.clear();
    for (final b in Brightness.values) {
      t.platformDispatcher.platformBrightnessTestValue = b;
      await t.pumpWidget(const PapyrApp());
      await t.pumpAndSettle();
      final region = t.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(region.value.systemNavigationBarContrastEnforced, isFalse);
    }
  });

  // Android 15+ derives FORCE_LIGHT_NAVIGATION_BARS from the window background unless the theme names a nav bar
  // color, and never recomputes it on a uiMode change the activity handles itself
  test('NormalTheme names a transparent nav bar in both themes', () {
    for (final dir in ['values', 'values-night']) {
      final xml = File('android/app/src/main/res/$dir/styles.xml').readAsStringSync();
      final normal = RegExp(r'<style name="NormalTheme".*?</style>', dotAll: true).firstMatch(xml)![0]!;
      expect(normal, contains('<item name="android:navigationBarColor">@android:color/transparent</item>'), reason: dir);
    }
  });
}
