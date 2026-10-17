import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/scan/detector.dart';

const w = 240, h = 320;
typedef P = (double, double);

bool inside(List<P> q, double x, double y) {
  for (var i = 0; i < 4; i++) {
    final (ax, ay) = q[i];
    final (bx, by) = q[(i + 1) % 4];
    if ((bx - ax) * (y - ay) - (by - ay) * (x - ax) < 0) return false;
  }
  return true;
}

Uint8List scene({required double Function(int x, int y) bg, List<P>? quad, double Function(int x, int y)? page,
    bool text = false, double noise = 3, int seed = 1, void Function(Float64List img)? extra}) {
  final img = Float64List(w * h);
  final cx = quad == null ? 0.0 : quad.fold(0.0, (s, p) => s + p.$1) / 4;
  final cy = quad == null ? 0.0 : quad.fold(0.0, (s, p) => s + p.$2) / 4;
  final inner = [for (final (x, y) in quad ?? <P>[]) (cx + 0.8 * (x - cx), cy + 0.8 * (y - cy))];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = bg(x, y);
      if (quad != null) {
        var c = 0;
        for (var sy = 0; sy < 4; sy++) {
          for (var sx = 0; sx < 4; sx++) {
            if (inside(quad, x + (sx + 0.5) / 4, y + (sy + 0.5) / 4)) c++;
          }
        }
        var p = page!(x, y);
        if (text && y % 16 < 2 && inside(inner, x + 0.5, y + 0.5)) p -= 120;
        v += (p - v) * c / 16;
      }
      img[y * w + x] = v;
    }
  }
  extra?.call(img);
  final out = Uint8List(w * h), rnd = Random(seed);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) { s += img[(y + dy).clamp(0, h - 1) * w + (x + dx).clamp(0, w - 1)]; }
      }
      final g = sqrt(-2 * log(1 - rnd.nextDouble())) * cos(2 * pi * rnd.nextDouble());
      out[y * w + x] = (s / 9 + noise * g).round().clamp(0, 255);
    }
  }
  return out;
}

void Function(Float64List) rects(List<(int, int, int, int, double)> rs) => (img) {
      for (final (x0, y0, x1, y1, v) in rs) {
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) { img[y * w + x] = v; }
        }
      }
    };

double Function(int, int) k(double v) => (_, _) => v;

List<double>? detect(Uint8List img) {
  final r = detectQuad(img, w, h);
  if (r != null) {
    expect(r.length, 8);
    expect(r.every((v) => v >= 0 && v <= 1), isTrue, reason: '$r');
  }
  return r;
}

void expectQuad(List<double>? got, List<P> want, {double tol = 0.03}) {
  expect(got, isNotNull);
  for (var i = 0; i < 4; i++) {
    expect((got![2 * i] - (want[i].$1 / 240).clamp(0, 1)).abs(), lessThan(tol), reason: 'x$i');
    expect((got[2 * i + 1] - (want[i].$2 / 320).clamp(0, 1)).abs(), lessThan(tol), reason: 'y$i');
  }
}

void main() {
  const persp = <P>[(40, 50), (205, 35), (215, 290), (30, 275)];

  test('perspective sheet with text', () {
    expectQuad(detect(scene(bg: k(60), quad: persp, page: k(200), text: true, noise: 4)), persp);
  });

  test('low contrast', () {
    expectQuad(detect(scene(bg: k(120), quad: persp, page: k(140))), persp);
  });

  test('white sheet on light desk with light gradient', () {
    const q = <P>[(35, 45), (210, 40), (205, 285), (40, 280)];
    double f(int y) => 0.75 + 0.25 * y / 320;
    expectQuad(detect(scene(bg: (_, y) => 195 * f(y), quad: q, page: (_, y) => 235 * f(y))), q);
  });

  test('clutter touching the sheet', () {
    const q = <P>[(50, 60), (190, 50), (200, 270), (45, 280)];
    final img = scene(bg: k(70), quad: q, page: k(210), extra: rects([(193, 140, 235, 150, 20), (0, 280, 40, 320, 130)]));
    expectQuad(detect(img), q);
  });

  test('sheet touching the left border', () {
    const q = <P>[(0, 40), (200, 30), (210, 300), (0, 290)];
    expectQuad(detect(scene(bg: k(60), quad: q, page: k(210))), q);
  });

  test('corner cut by the frame', () {
    const q = <P>[(-20, -15), (210, 25), (220, 300), (25, 290)];
    expectQuad(detect(scene(bg: k(60), quad: q, page: k(210))), q);
  });

  test('sheet rotated about 45 degrees', () {
    const q = <P>[(125, 45), (222, 165), (118, 282), (18, 158)];
    final r = detect(scene(bg: k(60), quad: q, page: k(210)))!;
    final pts = [for (var i = 0; i < 4; i++) (r[2 * i], r[2 * i + 1])];
    for (var i = 0; i < 4; i++) {
      for (var j = i + 1; j < 4; j++) {
        expect(sqrt(pow(pts[i].$1 - pts[j].$1, 2) + pow(pts[i].$2 - pts[j].$2, 2)), greaterThan(0.1));
      }
    }
    for (final (x, y) in q) {
      expect(pts.any((p) => (p.$1 - x / 240).abs() < 0.03 && (p.$2 - y / 320).abs() < 0.03), isTrue, reason: '($x, $y)');
    }
    var area = 0.0;
    for (var i = 0; i < 4; i++) {
      final (ax, ay) = pts[i];
      final (bx, by) = pts[(i + 1) % 4];
      area += ax * 240 * by * 320 - bx * 240 * ay * 320;
    }
    expect(area, greaterThan(0));
    final sums = [for (final (x, y) in pts) x * 240 + y * 320];
    expect(sums.indexOf(sums.reduce(min)), 0);
  });

  test('no sheet: noise', () {
    expect(detect(scene(bg: k(128), noise: 20, seed: 2)), isNull);
  });

  test('no sheet: texture', () {
    expect(detect(scene(bg: (x, y) => 128 + 40 * sin(x / 3 + 2 * sin(y / 17)), noise: 6)), isNull);
  });

  test('no sheet: smooth gradient', () {
    expect(detect(scene(bg: (x, _) => 40 + 180 * x / 240, noise: 2)), isNull);
  });

  test('no sheet: small rectangles', () {
    const tl = [(20, 20), (150, 30), (60, 120), (170, 150), (30, 250), (160, 270)];
    expect(detect(scene(bg: k(60), extra: rects([for (final (x, y) in tl) (x, y, x + 30, y + 20, 220)]))), isNull);
  });

  test('smoothQuad aligns cyclic labels before averaging', () {
    const prev = [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9];
    final rotated = [0.9, 0.1, 0.9, 0.9, 0.1, 0.9, 0.1, 0.1]; // mesmos cantos, começando no TR
    final r = smoothQuad(prev, rotated);
    for (var i = 0; i < 8; i++) { expect(r[i], closeTo(prev[i], 1e-9)); }
    final shifted = [for (var i = 0; i < 8; i++) prev[i] + (i.isEven ? 0.1 : 0)];
    expect(smoothQuad(prev, shifted)[0], closeTo(0.15, 1e-9));
  });

  test('detectQuad 50x on 240x320 runs under 1s', () {
    final img = scene(bg: k(60), quad: persp, page: k(200), text: true, noise: 4);
    detectQuad(img, w, h);
    final sw = Stopwatch()..start();
    for (var i = 0; i < 50; i++) { detectQuad(img, w, h); }
    sw.stop();
    // ignore: avoid_print
    print('detectQuad mean ${(sw.elapsedMicroseconds / 50 / 1000).toStringAsFixed(2)} ms');
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });
}
