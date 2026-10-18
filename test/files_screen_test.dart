import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/files/files_screen.dart';
import 'package:papyr/format.dart';
import 'package:papyr/library.dart';
import 'package:papyr/theme.dart';
import 'package:papyr/widgets/papyr_mark.dart';
import 'package:papyr/widgets/snake_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var items = <Map<String, Object?>>[];
  var listFails = false;

  setUp(() {
    calls.clear();
    listFails = false;
    // the singleton outlives each test, and a failed list keeps the old items
    library.items = [];
    library.error = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('papyr/native'), (c) async {
        calls.add(c);
        switch (c.method) {
          case 'list':
            if (listFails) throw PlatformException(code: 'io');
            return items;
          case 'delete': items = []; return null;
          case 'thumbnail': throw PlatformException(code: 'decode');
        }
        return null;
      });
  });

  Future<void> pump(WidgetTester t, [Widget home = const Scaffold(body: FilesScreen())]) async {
    await t.pumpWidget(MaterialApp(theme: papyrTheme(Brightness.light), home: home));
    await library.refresh();
    await t.pumpAndSettle();
  }

  testWidgets('empty list points to the scan button', (t) async {
    items = [];
    await pump(t);
    expect(find.text('Nada escaneado ainda'), findsOneWidget);
    expect(find.text('Toque no botão do meio para fotografar sua primeira folha.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(PapyrMark), findsOneWidget);
  });

  testWidgets('rows grouped by day with type, size and time; failed thumbnail shows placeholder', (t) async {
    items = [
      {'uri': 'content://f/2', 'name': 'Contrato.pdf', 'mime': 'application/pdf', 'size': 12897485,
       'date': DateTime(2026, 10, 17, 14, 5).millisecondsSinceEpoch},
      {'uri': 'content://i/1', 'name': 'Recibo.jpg', 'mime': 'image/jpeg', 'size': 1536,
       'date': DateTime(2026, 10, 16, 9, 0).millisecondsSinceEpoch},
    ];
    await pump(t);
    final now = DateTime.now();
    final d17 = formatDay(DateTime(2026, 10, 17, 14, 5), now), d16 = formatDay(DateTime(2026, 10, 16, 9), now);
    expect(find.text('Seus documentos'), findsOneWidget);
    expect(find.text('2 arquivos, 12,3 MB'), findsOneWidget);
    expect(find.text('PDF, 12,3 MB, 14:05'), findsOneWidget);
    expect(find.text('Imagem, 1,5 KB, 09:00'), findsOneWidget);
    expect(find.text('IMG'), findsNothing);
    double y(Finder f) => t.getTopLeft(f).dy;
    expect(y(find.text(d17)), lessThan(y(find.text('Contrato.pdf'))));
    expect(y(find.text('Contrato.pdf')), lessThan(y(find.text(d16))));
    expect(y(find.text(d16)), lessThan(y(find.text('Recibo.jpg'))));
    expect(t.takeException(), isNull);
  });

  testWidgets('load error offers retry', (t) async {
    listFails = true;
    await pump(t);
    expect(find.text('Não foi possível carregar os arquivos.'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Tentar de novo'));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.method == 'list').length, 2);
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
    expect(find.text('Nada escaneado ainda'), findsOneWidget);
  });

  // Review Focus 1
  testWidgets('200% text on a 360 dp phone does not overflow', (t) async {
    t.view
      ..physicalSize = const Size(360, 690)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    items = [
      {'uri': 'content://f/2', 'name': 'Contrato de locação residencial assinado' * 3, 'mime': 'application/pdf',
       'size': 12897485, 'date': DateTime(2026, 10, 17, 14, 5).millisecondsSinceEpoch},
    ];
    await pump(
      t,
      Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2)),
          child: const Scaffold(body: FilesScreen()),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });

  // Review Focus 3
  testWidgets('last row clears the scan button', (t) async {
    items = [
      for (var i = 0; i < 30; i++) {'uri': 'content://i/$i', 'name': 'item$i.jpg', 'mime': 'image/jpeg', 'size': 10, 'date': 0},
    ];
    await pump(
      t,
      Scaffold(
        body: const FilesScreen(),
        floatingActionButton: ScanButton(onPressed: () {}),
        floatingActionButtonLocation: scanButtonLocation,
        bottomNavigationBar: SnakeBar(
          index: 0,
          onTap: (_) {},
          items: const [(Icons.folder_outlined, 'Arquivos'), null, (Icons.settings_outlined, 'Ajustes')],
        ),
      ),
    );
    await t.drag(find.byType(CustomScrollView), const Offset(0, -10000));
    await t.pumpAndSettle();
    final last = t.getRect(find.ancestor(of: find.text('item29.jpg'), matching: find.byType(InkWell)).first);
    expect(last.bottom, lessThanOrEqualTo(t.getRect(find.byType(ScanButton)).top));
  });
}
