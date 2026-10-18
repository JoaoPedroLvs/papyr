import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/library.dart';
import 'package:papyr/main.dart';
import 'package:papyr/settings_screen.dart';
import 'package:papyr/theme.dart';
import 'package:papyr/widgets/papyr_mark.dart';
import 'package:papyr/widgets/snake_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const a = {'uri': 'content://i/1', 'name': 'a.jpg', 'mime': 'image/jpeg', 'size': 1048576, 'date': 0};
  const b = {'uri': 'content://i/2', 'name': 'b.jpg', 'mime': 'image/jpeg', 'size': 524288, 'date': 0};
  const c = {'uri': 'content://f/3', 'name': 'c.pdf', 'mime': 'application/pdf', 'size': 1048576, 'date': 0};
  var list = <Map<String, Object?>>[];

  setUp(() {
    list = [a, b, c];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('papyr/native'), (call) async {
        switch (call.method) {
          case 'list': return list;
          case 'appVersion': return '1.0.0';
        }
        return null;
      });
  });

  Future<void> pump(WidgetTester t, {Widget? host, double textScale = 1}) async {
    await t.pumpWidget(MaterialApp(
      theme: papyrTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: host ?? const Scaffold(body: SettingsScreen()),
    ));
    await library.refresh();
    await t.pumpAndSettle();
  }

  testWidgets('shows space used, folders, note and version', (t) async {
    await pump(t);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Espaço usado'), findsOneWidget);
    expect(find.text('2,5 MB em 2 imagens e 1 PDF', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('meter')), findsOneWidget);
    expect(find.text('Imagens 1,5 MB'), findsOneWidget);
    expect(find.text('PDFs 1,0 MB'), findsOneWidget);
    expect(find.text('Onde ficam os arquivos'), findsOneWidget);
    for (final s in ['Imagens', 'Pictures/Papyr', 'PDFs', 'Documents/Papyr']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('Desinstalar o Papyr não apaga seus arquivos, mas eles deixam de aparecer aqui.'), findsOneWidget);
    expect(find.text('Versão 1.0.0'), findsOneWidget);
    expect(find.bySemanticsLabel('Papyr'), findsOneWidget);
    expect(find.byType(PapyrMark), findsOneWidget);
  });

  testWidgets('nothing saved hides the meter', (t) async {
    list = [];
    await pump(t);
    expect(find.text('Nada salvo ainda'), findsOneWidget);
    expect(find.byKey(const ValueKey('meter')), findsNothing);
    expect(find.textContaining('Imagens 0'), findsNothing);
  });

  testWidgets('only PDFs leaves images out', (t) async {
    list = [c];
    await pump(t);
    expect(find.text('1,0 MB em 1 PDF', findRichText: true), findsOneWidget);
    expect(find.textContaining('Imagens '), findsNothing);
  });

  // Review Focus 1
  testWidgets('200% text on a 360 dp phone does not overflow', (t) async {
    t.view
      ..physicalSize = const Size(360, 690)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await pump(t, textScale: 2);
    expect(t.takeException(), isNull);
  });

  // Review Focus 3: the centred colophon sits right where the scan button rises
  testWidgets('version clears the scan button', (t) async {
    await pump(t, host: Scaffold(
      body: const SettingsScreen(),
      floatingActionButton: ScanButton(onPressed: () {}),
      floatingActionButtonLocation: scanButtonLocation,
      bottomNavigationBar: SnakeBar(
        index: 2,
        onTap: (_) {},
        items: const [(Icons.folder_outlined, 'Arquivos'), null, (Icons.settings_outlined, 'Ajustes')],
      ),
    ));
    await t.drag(find.byType(CustomScrollView), const Offset(0, -10000)); // fits or not, check at the end
    await t.pumpAndSettle();
    expect(t.getRect(find.text('Versão 1.0.0')).bottom, lessThanOrEqualTo(t.getRect(find.byType(ScanButton)).top));
  });

  testWidgets('tab 2 is the settings screen', (t) async {
    tab.value = 2;
    await t.pumpWidget(const PapyrApp());
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(SnakeBar), findsOneWidget);
    expect(find.byType(ScanButton), findsOneWidget);
  });
}
