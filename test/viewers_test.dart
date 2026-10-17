import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/files/files_screen.dart';
import 'package:papyr/library.dart';

import 'jpeg_fixtures.dart';

void main() {
  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall c)> handlers;

  final pdf = {'uri': 'content://f/2', 'name': 'Contrato.pdf', 'mime': 'application/pdf', 'size': 10, 'date': 0};
  final jpg = {'uri': 'content://i/1', 'name': 'Recibo.jpg', 'mime': 'image/jpeg', 'size': 10, 'date': 0};

  setUp(() {
    calls = [];
    handlers = {
      'list': (_) => [pdf, jpg],
      'thumbnail': (_) => throw PlatformException(code: 'decode'),
      'pdfInfo': (_) => 3,
      'pdfPage': (_) => tinyJpeg,
      'read': (_) => tinyJpeg,
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('papyr/native'), (c) async {
        calls.add(c);
        return handlers[c.method]?.call(c);
      });
  });

  Future<void> openRow(WidgetTester t, String name) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: FilesScreen())));
    await library.refresh();
    await t.pumpAndSettle();
    await t.tap(find.text(name));
    await t.pumpAndSettle();
  }

  int lists() => calls.where((c) => c.method == 'list').length;

  testWidgets('tapping a PDF opens the PDF viewer with a page indicator', (t) async {
    await openRow(t, 'Contrato.pdf');
    expect(find.text('1 / 3'), findsOneWidget);
    expect(calls.where((c) => c.method == 'pdfPage').first.arguments, containsPair('index', 0));
  });

  testWidgets('a file deleted elsewhere closes the viewer with a message and refreshes the list', (t) async {
    handlers['read'] = (_) => throw PlatformException(code: 'not_found');
    await openRow(t, 'Recibo.jpg');
    expect(find.text('O arquivo não existe mais.'), findsOneWidget);
    expect(find.byType(FilesScreen), findsOneWidget);
    expect(find.byTooltip('Excluir'), findsNothing);
    expect(lists(), greaterThanOrEqualTo(2));
  });

  testWidgets('deleting from the image viewer confirms, closes and shows the snackbar', (t) async {
    await openRow(t, 'Recibo.jpg');
    await t.tap(find.byTooltip('Excluir'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Excluir'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.method == 'delete').single.arguments, {'uri': 'content://i/1'});
    expect(find.byTooltip('Excluir'), findsNothing);
    expect(find.text('Arquivo excluído'), findsOneWidget);
  });

  testWidgets('cancelling the delete keeps the viewer open', (t) async {
    await openRow(t, 'Recibo.jpg');
    await t.tap(find.byTooltip('Excluir'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Excluir'), findsOneWidget);
  });

  testWidgets('pinch-zooming a PDF page locks the swipe until zoom returns to 1', (t) async {
    await openRow(t, 'Contrato.pdf');
    ScrollPhysics? physics() => t.widget<PageView>(find.byType(PageView)).physics;
    expect(physics(), isNull);
    final c = t.getCenter(find.byType(InteractiveViewer).first);
    final a = await t.startGesture(c - const Offset(20, 0));
    final b = await t.startGesture(c + const Offset(20, 0), pointer: 2);
    for (var i = 1; i <= 10; i++) {
      await a.moveTo(c - Offset(20.0 + 8 * i, 0));
      await b.moveTo(c + Offset(20.0 + 8 * i, 0));
      await t.pump();
    }
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    expect(physics(), isA<NeverScrollableScrollPhysics>());
    final a2 = await t.startGesture(c - const Offset(100, 0));
    final b2 = await t.startGesture(c + const Offset(100, 0), pointer: 4);
    for (var i = 1; i <= 10; i++) {
      await a2.moveTo(c - Offset(100.0 - 9 * i, 0));
      await b2.moveTo(c + Offset(100.0 - 9 * i, 0));
      await t.pump();
    }
    await a2.up();
    await b2.up();
    await t.pumpAndSettle();
    expect(physics(), isNull);
  });
}
