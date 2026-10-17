import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/main.dart' show tab;
import 'package:papyr/scan/save_screen.dart';
import 'package:papyr/scan/session.dart';

void main() {
  late List<MethodCall> calls;
  var failWarp = false;

  setUp(() {
    calls = [];
    failWarp = false;
    session.clear();
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

  // runSave deletes its temp file with real I/O, which never completes inside FakeAsync.
  Future<void> tapAndRun(WidgetTester t, String label) async {
    await t.tap(find.widgetWithText(FilledButton, label));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
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
}
