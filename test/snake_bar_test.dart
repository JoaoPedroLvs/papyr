import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/theme.dart';
import 'package:papyr/widgets/snake_bar.dart';

void main() {
  int? tapped;
  late ValueNotifier<int> index;

  // index comes from a notifier, so a switch updates the bar instead of remounting it
  Future<void> host(WidgetTester t, {double inset = 0, bool reduceMotion = false}) async {
    tapped = null;
    index = ValueNotifier(0);
    await t.pumpWidget(MaterialApp(
      theme: papyrTheme(Brightness.light),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            viewPadding: EdgeInsets.only(bottom: inset),
            padding: EdgeInsets.only(bottom: inset),
            disableAnimations: reduceMotion,
          ),
          child: ValueListenableBuilder(
            valueListenable: index,
            builder: (_, i, _) => Scaffold(
              floatingActionButton: ScanButton(onPressed: () => tapped = 1),
              floatingActionButtonLocation: scanButtonLocation,
              bottomNavigationBar: SnakeBar(index: i, onTap: (v) => tapped = v, items: const [
                (Icons.folder_outlined, 'Arquivos'),
                null,
                (Icons.settings_outlined, 'Ajustes'),
              ]),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('side items fill their column: centred, tappable near the bottom edge', (t) async {
    await host(t);
    final bar = t.getRect(find.byType(SnakeBar));
    expect(t.getCenter(find.byIcon(Icons.folder_outlined)).dy, bar.center.dy);
    expect(t.getCenter(find.byIcon(Icons.settings_outlined)).dy, bar.center.dy);
    await t.tapAt(Offset(t.getCenter(find.byIcon(Icons.settings_outlined)).dx, bar.bottom - 10));
    expect(tapped, 2);
  });

  testWidgets('Arquivos column takes the tap back from Ajustes', (t) async {
    await host(t);
    index.value = 2;
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.folder_outlined));
    expect(tapped, 0);
  });

  testWidgets('three items evenly spaced', (t) async {
    await host(t);
    final w = t.getSize(find.byType(SnakeBar)).width;
    expect(t.getCenter(find.byIcon(Icons.folder_outlined)).dx, closeTo(w / 6, 0.5));
    expect(t.getCenter(find.byType(ScanButton)).dx, closeTo(w / 2, 0.5));
    expect(t.getCenter(find.byIcon(Icons.settings_outlined)).dx, closeTo(5 * w / 6, 0.5));
  });

  // Review Focus 5: with a 3-button nav inset too
  for (final inset in [0.0, 48.0]) {
    testWidgets('scan button rises 22 dp and its raised top takes taps (inset $inset)', (t) async {
      await host(t, inset: inset);
      final bar = t.getRect(find.byType(SnakeBar));
      final scan = t.getRect(find.byType(ScanButton));
      expect(bar.height, 64 + inset);
      expect(scan.top, bar.top - 22);
      expect(scan.size, const Size(62, 62));
      await t.tapAt(Offset(scan.center.dx, scan.top + 4));
      expect(tapped, 1);
    });
  }

  testWidgets('labels for screen readers and tap targets', (t) async {
    await host(t);
    expect(find.bySemanticsLabel('Arquivos'), findsOneWidget);
    expect(find.bySemanticsLabel('Escanear'), findsOneWidget);
    expect(find.bySemanticsLabel('Ajustes'), findsOneWidget);
    expect(find.text('Arquivos'), findsNothing); // no visible label
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  });

  // Review Focus 5
  testWidgets('pill ends under the active item after an interrupted switch', (t) async {
    await host(t);
    index.value = 2;
    await t.pump(const Duration(milliseconds: 100));
    index.value = 0;
    await t.pumpAndSettle();
    expect(t.getCenter(find.byKey(const ValueKey('pill'))).dx,
        closeTo(t.getCenter(find.byIcon(Icons.folder_outlined)).dx, 0.5));
  });

  testWidgets('reduced motion: pill jumps', (t) async {
    await host(t, reduceMotion: true);
    index.value = 2;
    await t.pump();
    expect(t.getCenter(find.byKey(const ValueKey('pill'))).dx,
        closeTo(t.getCenter(find.byIcon(Icons.settings_outlined)).dx, 0.5));
  });
}
