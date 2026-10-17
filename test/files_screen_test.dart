import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/files/files_screen.dart';
import 'package:papyr/library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var items = <Map<String, Object?>>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('papyr/native'), (c) async {
        calls.add(c);
        switch (c.method) {
          case 'list': return items;
          case 'delete': items = []; return null;
          case 'thumbnail': throw PlatformException(code: 'decode');
        }
        return null;
      });
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: FilesScreen())));
    await library.refresh();
    await t.pumpAndSettle();
  }

  testWidgets('empty list shows call to action', (t) async {
    items = [];
    await pump(t);
    expect(find.text('Nenhum arquivo ainda'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Escanear'), findsOneWidget);
  });

  testWidgets('rows show name, badge, date and size; failed thumbnail shows placeholder', (t) async {
    items = [
      {'uri': 'content://f/2', 'name': 'Contrato.pdf', 'mime': 'application/pdf', 'size': 12897485,
       'date': DateTime(2026, 10, 17, 14, 5).millisecondsSinceEpoch},
      {'uri': 'content://i/1', 'name': 'Recibo.jpg', 'mime': 'image/jpeg', 'size': 1536,
       'date': DateTime(2026, 10, 16, 9, 0).millisecondsSinceEpoch},
    ];
    await pump(t);
    expect(find.text('Contrato.pdf'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('IMG'), findsOneWidget);
    expect(find.text('17/10/2026 14:05 · 12,3 MB'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('delete asks for confirmation, deletes and refreshes', (t) async {
    items = [
      {'uri': 'content://i/1', 'name': 'Recibo.jpg', 'mime': 'image/jpeg', 'size': 1, 'date': 0},
    ];
    await pump(t);
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('Excluir'));
    await t.pumpAndSettle();
    expect(find.text('Excluir arquivo?'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Excluir'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.method == 'delete').single.arguments, {'uri': 'content://i/1'});
    expect(calls.where((c) => c.method == 'list').length, 2);
    expect(find.text('Nenhum arquivo ainda'), findsOneWidget);
  });
}
