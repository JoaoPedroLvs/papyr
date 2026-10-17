import 'dart:math';
import 'dart:typed_data';

/// Camera Y plane → upright grayscale (at most [maxSide] px, 2x2 average per sample), or null for a short buffer.
/// Normalized coords of the result map 1:1 onto CameraPreview's child.
// ponytail: assumes display rotation 0 (phone portrait); tablets need (sensor - displayRotation)
(Uint8List, int, int)? uprightLuma(Uint8List y, int rowStride, int w, int h, int sensorDeg, {int maxSide = 320}) {
  if (y.length < (h - 1) * rowStride + w) return null; // the last row has no padding
  final s = min(1.0, maxSide / max(w, h));
  final sw = max(1, (w * s).round()), sh = max(1, (h * s).round());
  final swap = sensorDeg % 180 != 0;
  final ow = swap ? sh : sw, oh = swap ? sw : sh;
  final out = Uint8List(ow * oh);
  for (var oy = 0; oy < oh; oy++) {
    for (var ox = 0; ox < ow; ox++) {
      final (bx, by) = switch (sensorDeg) {
        90 => (oy, sh - 1 - ox),
        270 => (sw - 1 - oy, ox),
        180 => (sw - 1 - ox, sh - 1 - oy),
        _ => (ox, oy),
      };
      final int i = min(by * h ~/ sh, h - 2) * rowStride + min(bx * w ~/ sw, w - 2);
      out[oy * ow + ox] = (y[i] + y[i + 1] + y[i + rowStride] + y[i + rowStride + 1] + 2) >> 2;
    }
  }
  return (out, ow, oh);
}
