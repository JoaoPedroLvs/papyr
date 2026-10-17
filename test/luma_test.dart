import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/scan/luma.dart';

void main() {
  test('uprightLuma rotates sensor 90 into portrait and averages', () {
    const w = 640, h = 480, stride = 704;
    final y = Uint8List((h - 1) * stride + w); // última linha sem padding
    for (var r = 0; r < h; r++) {
      for (var c = 0; c < w; c++) { y[r * stride + c] = c < w ~/ 2 ? 0 : 255; }
    }
    final (px, ow, oh) = uprightLuma(y, stride, w, h, 90)!;
    expect((ow, oh), (240, 320));
    expect(px.sublist(0, ow).every((v) => v < 10), isTrue);                 // topo = esquerda do sensor
    expect(px.sublist((oh - 1) * ow).every((v) => v > 245), isTrue);        // base = direita do sensor
    final (_, w0, h0) = uprightLuma(y, stride, w, h, 0)!;
    expect((w0, h0), (320, 240));
    expect(uprightLuma(Uint8List(100), stride, w, h, 90), isNull);
  });
}
