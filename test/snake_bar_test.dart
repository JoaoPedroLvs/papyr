import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/widgets/snake_bar.dart';

void main() {
  testWidgets('items fill the bar height: centred and tappable across the whole pill', (t) async {
    int? tapped;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: SnakeBar(index: 0, onTap: (i) => tapped = i, items: const [
          (Icons.folder_outlined, 'Arquivos'),
          (Icons.document_scanner_outlined, 'Escanear'),
          (Icons.settings_outlined, 'Ajustes'),
        ]),
      ),
    ));
    final bar = t.getRect(find.byType(SnakeBar));
    expect(t.getCenter(find.byIcon(Icons.folder_outlined)).dy, bar.center.dy);
    expect(t.getCenter(find.byIcon(Icons.settings_outlined)).dy, bar.center.dy);
    await t.tapAt(Offset(t.getCenter(find.byIcon(Icons.settings_outlined)).dx, bar.bottom - 10));
    expect(tapped, 2);
  });
}
