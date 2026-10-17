import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/scan/crop_screen.dart';
import 'package:papyr/scan/session.dart';

void main() {
  test('isConvex', () {
    expect(isConvex(fullQuad), isTrue);
    expect(isConvex([0.1, 0.2, 0.9, 0.1, 0.8, 0.9, 0.2, 0.8]), isTrue);
    expect(isConvex([0, 0, 1, 1, 1, 0, 0, 1]), isFalse); // gravata-borboleta
    expect(isConvex([0, 0, 1, 0, 0.4, 0.4, 0, 1]), isFalse); // côncavo
    expect(isConvex([0, 0, 0.5, 0, 1, 0, 0, 1]), isFalse); // 3 pontos colineares
  });

  testWidgets('editor detects into photo.detected and keeps the user corners', (tester) async {
    const q = [0.2, 0.15, 0.8, 0.2, 0.85, 0.85, 0.15, 0.8];
    final png = (await tester.runAsync(() async {
      final r = ui.PictureRecorder();
      Canvas(r)
        ..drawColor(const Color(0xFF303030), BlendMode.src)
        ..drawPath(Path()..addPolygon([for (var i = 0; i < 8; i += 2) Offset(q[i] * 600, q[i + 1] * 800)], true),
            Paint()..color = const Color(0xFFE0E0E0));
      final img = await r.endRecording().toImage(600, 800);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    }))!;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('papyr/native'), (c) async => {'bytes': png, 'width': 600, 'height': 800});
    final edited = [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9];
    final photo = Photo('/x/CAP0.jpg')..corners = edited;
    session.add(photo);
    addTearDown(session.clear);
    await tester.pumpWidget(const MaterialApp(home: CropScreen()));
    for (var i = 0; i < 100 && photo.detected == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(photo.detected, [for (final v in q) closeTo(v, 0.03)]);
    expect(photo.corners, same(edited));
  });
}
