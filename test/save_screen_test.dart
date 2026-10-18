import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/main.dart' show tab;
import 'package:papyr/scan/save_screen.dart';
import 'package:papyr/scan/session.dart';
import 'package:papyr/widgets/papyr_mark.dart';

void main() {
  late List<MethodCall> calls;
  var failWarp = false;

  setUp(() {
    calls = [];
    failWarp = false;
    session.clear();
    session.detecting = Future.value(); // a future from an earlier test's zone would never complete here
    tab.value = 1;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('papyr/native'), (c) async {
        calls.add(c);
        switch (c.method) {
          case 'warp':
            if (failWarp) throw PlatformException(code: 'decode');
            return {'path': '/nonexistent/papyr_w_1.jpg', 'width': 4, 'height': 4};
          case 'save':
            return {'uri': 'content://x/1', 'name': c.arguments['name'], 'size': 1, 'date': 0};
          case 'list':
            return <Object?>[];
        }
        return null;
      });
  });

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(home: Builder(
      builder: (context) => Scaffold(body: TextButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SaveScreen())),
        child: const Text('home'),
      )),
    )));
    await t.tap(find.text('home'));
    await t.pumpAndSettle();
  }

  // runSave deletes its temp file with real I/O, which never completes inside FakeAsync:
  // alternate fake pumps (channel replies) with real time (file deletes).
  Future<void> settleIo(WidgetTester t) async {
    for (var i = 0; i < 10; i++) {
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await t.pumpAndSettle();
  }

  Future<void> tapAndRun(WidgetTester t, String label) async {
    await t.tap(find.widgetWithText(FilledButton, label));
    await settleIo(t);
  }

  testWidgets('one photo: saves as image, clears the session and back acts like Concluir', (t) async {
    session.add(Photo('/c/CAP0.jpg'));
    await open(t);
    expect(find.text('Nome'), findsOneWidget);
    await t.enterText(find.byType(TextField), '  Recibo/1 ');
    await tapAndRun(t, 'Salvar');
    expect(find.text('Salvo'), findsOneWidget);
    expect(calls.singleWhere((c) => c.method == 'save').arguments['name'], 'Recibo1.jpg');
    expect(session.photos, isEmpty);
    expect(calls.where((c) => c.method == 'cleanCache'), hasLength(1));
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(tab.value, 0);
    expect(calls.where((c) => c.method == 'list'), hasLength(1));
  });

  testWidgets('done shows the mark and Salvo', (t) async {
    session.add(Photo('/c/CAP0.jpg'));
    await open(t);
    await tapAndRun(t, 'Salvar');
    expect(find.text('Salvo'), findsOneWidget);
    expect(find.byType(PapyrMark), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });

  // Review Focus 1: the title in the body must not push Salvar under the keyboard at large text
  testWidgets('200% text with the keyboard up does not overflow', (t) async {
    t.view
      ..physicalSize = const Size(360, 690)
      ..devicePixelRatio = 1
      ..viewInsets = const FakeViewPadding(bottom: 280);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    session.add(Photo('/c/CAP0.jpg'));
    await open(t);
    expect(t.takeException(), isNull);
    final salvar = find.widgetWithText(FilledButton, 'Salvar');
    await t.ensureVisible(salvar);
    await t.pumpAndSettle();
    expect(t.getRect(salvar).bottom, lessThanOrEqualTo(690 - 280));
  });

  testWidgets('failure keeps the session, explains and retries', (t) async {
    session.add(Photo('/c/CAP0.jpg'));
    failWarp = true;
    await open(t);
    await tapAndRun(t, 'Salvar');
    expect(find.text('Falha ao processar a foto 1.'), findsOneWidget);
    expect(session.photos, hasLength(1));
    failWarp = false;
    await tapAndRun(t, 'Tentar de novo');
    expect(find.text('Salvo'), findsOneWidget);
  });

  SaveMode selected(WidgetTester t) => t.widget<SegmentedButton<SaveMode>>(find.byType(SegmentedButton<SaveMode>)).selected.single;

  testWidgets('starts in PDF with more than one photo', (t) async {
    session..add(Photo('/c/CAP0.jpg'))..add(Photo('/c/CAP1.jpg'));
    await open(t);
    expect(selected(t), SaveMode.pdf);
  });

  testWidgets('after a partial Imagens save the format is Imagens and locked', (t) async {
    session..add(Photo('/c/CAP0.jpg')..savedUri = 'content://x/1')..add(Photo('/c/CAP1.jpg'));
    await open(t);
    expect(selected(t), SaveMode.images);
    expect(t.widget<SegmentedButton<SaveMode>>(find.byType(SegmentedButton<SaveMode>)).onSelectionChanged, isNull);
  });

  testWidgets('saving waits for the editor detection still running', (t) async {
    final pending = Completer<void>();
    session
      ..add(Photo('/c/CAP0.jpg'))
      ..detecting = pending.future;
    await open(t);
    await t.tap(find.widgetWithText(FilledButton, 'Salvar'));
    await t.pump();
    expect(calls.where((c) => c.method == 'warp'), isEmpty);
    session.photos.single.detected = [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9];
    pending.complete();
    await settleIo(t);
    expect(calls.singleWhere((c) => c.method == 'warp').arguments['corners'], [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]);
    expect(find.text('Salvo'), findsOneWidget);
  });

  testWidgets('name and format survive going back to the editor after a failure', (t) async {
    session..add(Photo('/c/CAP0.jpg'))..add(Photo('/c/CAP1.jpg'));
    failWarp = true;
    await open(t);
    await t.enterText(find.byType(TextField), 'Contrato');
    await t.tap(find.text('Imagens'));
    await t.pump();
    await tapAndRun(t, 'Salvar');
    expect(find.text('Falha ao processar a foto 1.'), findsOneWidget);
    await t.binding.handlePopRoute(); // back to the editor, as the message suggests
    await t.pumpAndSettle();
    await t.tap(find.text('home'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Contrato'), findsOneWidget);
    expect(selected(t), SaveMode.images);
  });
}
