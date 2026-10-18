import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/theme.dart';
import 'package:papyr/widgets/papyr_mark.dart';

/// Reads the boundary at pixelRatio 1 and returns the color at a logo coordinate, for a 300-wide mark.
Future<Color Function(double x, double y)> pixels(WidgetTester t, GlobalKey key) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late final ui.Image image;
  late final ByteData bytes;
  await t.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 1);
    bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  const s = 300 / 977;
  return (x, y) {
    final i = (((y - 330) * s).floor() * image.width + ((x - 535) * s).floor()) * 4;
    return Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
  };
}

Matcher closeToColor(Color c) => predicate<Color>(
  (p) => [p.a - c.a, p.r - c.r, p.g - c.g, p.b - c.b].every((d) => d.abs() <= 12 / 255),
  'close to $c',
);

void main() {
  testWidgets('full mark: size and colors where the logo has them', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(Center(child: RepaintBoundary(key: key, child: const PapyrMark(width: 300))));
    expect(t.getSize(find.byType(PapyrMark)), Size(300, 300 * markAspect));
    final px = await pixels(t, key);
    expect(px(1024, 851), closeToColor(Brand.green)); // scan line
    expect(px(650, 347), closeToColor(Brand.sky)); // top-left bracket arm
    expect(px(900, 700), closeToColor(const Color(0xFFFFFFFF))); // sheet
    expect(px(1056, 447), closeToColor(Brand.navy)); // sheet top edge
  });

  testWidgets('scan variant: brackets in the given color, no sheet', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(Center(
      child: RepaintBoundary(key: key, child: const PapyrMark.scan(width: 300, brackets: Brand.paper)),
    ));
    final px = await pixels(t, key);
    expect(px(650, 347), closeToColor(Brand.paper));
    expect(px(1024, 851), closeToColor(Brand.green));
    expect(px(900, 700).a, lessThan(0.05)); // transparent where the sheet would be
    expect(px(1024, 791).a, greaterThan(0.1)); // the glow, 60 units above the line (≈0.19 right, ≈0.02 if the sigma is scaled twice)
  });
}
