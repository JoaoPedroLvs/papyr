import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/scan/camera_screen.dart';
import 'package:papyr/scan/detector.dart';

void main() {
  test('trackQuad: EMA on hits, outline gone after 5 misses in a row', () {
    const a = [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9], b = [0.2, 0.2, 0.8, 0.2, 0.8, 0.8, 0.2, 0.8];
    var t = trackQuad(null, 0, a);
    expect((t.quad, t.misses), (a, 0));
    t = trackQuad(t.quad, t.misses, b);
    expect(t.quad, smoothQuad(a, b));
    final kept = t.quad;
    for (var i = 1; i <= 4; i++) {
      t = trackQuad(t.quad, t.misses, null);
      expect(t.quad, same(kept));
      expect(t.misses, i);
    }
    t = trackQuad(t.quad, t.misses, null);
    expect((t.quad, t.misses), (null, 5));
    t = trackQuad(t.quad, t.misses, a);
    expect((t.quad, t.misses), (a, 0));
  });

  test('QuadPainter repaints only for a new quad and paints null as nothing', () {
    const q = [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9];
    expect(QuadPainter(q).shouldRepaint(QuadPainter(q)), isFalse);
    expect(QuadPainter(q).shouldRepaint(QuadPainter([...q])), isTrue);
    expect(QuadPainter(null).shouldRepaint(QuadPainter(q)), isTrue);
    final canvas = Canvas(ui.PictureRecorder());
    QuadPainter(null).paint(canvas, const Size(100, 100));
    QuadPainter(q).paint(canvas, const Size(100, 100));
  });
}
