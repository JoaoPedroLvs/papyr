import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/library.dart';
import 'package:papyr/main.dart';
import 'package:papyr/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('papyr/native'), (c) async {
        switch (c.method) {
          case 'list': return [
            {'uri': 'content://i/1', 'name': 'a.jpg', 'mime': 'image/jpeg', 'size': 1048576, 'date': 0},
            {'uri': 'content://i/2', 'name': 'b.jpg', 'mime': 'image/jpeg', 'size': 524288, 'date': 0},
            {'uri': 'content://f/3', 'name': 'c.pdf', 'mime': 'application/pdf', 'size': 1048576, 'date': 0},
          ];
          case 'appVersion': return '1.0.0';
        }
        return null;
      });
  });

  testWidgets('shows space used, folders, uninstall warning and version', (t) async {
    await t.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await library.refresh();
    await t.pumpAndSettle();
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Espaço usado'), findsOneWidget);
    expect(find.text('2 imagens · 1 PDFs · 2,5 MB'), findsOneWidget);
    expect(find.text('Onde ficam os arquivos'), findsOneWidget);
    expect(find.text('Imagens em Pictures/Papyr e PDFs em Documents/Papyr'), findsOneWidget);
    expect(find.text('Desinstalar o Papyr não apaga seus arquivos, mas eles deixam de aparecer na lista do app.'),
        findsOneWidget);
    expect(find.text('Versão'), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
  });

  testWidgets('tab 2 is the settings screen', (t) async {
    tab.value = 2;
    await t.pumpWidget(const PapyrApp());
    await t.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
