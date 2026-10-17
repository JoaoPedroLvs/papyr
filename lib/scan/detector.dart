import 'dart:math' as math;
import 'dart:typed_data';

// Calibrated on synthetic scenes (spec 7).
const kMinHigh = 25.0, kNoiseK = 4.0, kLowRatio = 0.3;
const kMinBBoxFrac = 0.20, kMinAreaFrac = 0.20;
const kDpMin = 0.01, kDpMax = 0.05, kDpStep = 0.005;
const kSupportOffset = 3, kSupportTrim = 0.10, kMinDiff = 8, kMinSideSupport = 0.6;
const kBorderTolPx = 3.0, kBorderTolFrac = 0.015, kMaxBorderSides = 2;
const kRegionGrow = 2.0, kCutCornerMaxOut = 0.30;

/// Sheet corners TL, TR, BR, BL in a portrait gray image, normalized as (x + 0.5) / w and clamped to 0..1, or null.
List<double>? detectQuad(Uint8List gray, int w, int h) {
  final n = w * h, b = _blur(gray, w, h), mag = Float32List(n), dir = Uint8List(n);
  _sobel(b, w, h, mag, dir);
  final hi = math.max(kMinHigh, kNoiseK * _median(mag, w, h));
  final edges = _dilate(_hysteresis(_nms(mag, dir, w, h), w, h, hi, kLowRatio * hi), w, h);
  List<double>? best;
  var bestScore = 0.0;
  for (final edge in [true, false]) {
    for (final hull in _hulls(edges, edge, w, h)) {
      for (var q in _quads(hull, w, h)) {
        if (!edge) q = _grow(q, kRegionGrow); // the interior hull sits ~2 px inside the edge
        final area = _area(q);
        final score = area < kMinAreaFrac * n ? 0.0 : area * _support(b, w, h, q);
        if (score > bestScore) {
          bestScore = score;
          best = q;
        }
      }
    }
  }
  if (best == null) return null;
  var t = 0; // hull order is already TL→TR→BR→BL; start at min(x+y)
  for (var i = 1; i < 4; i++) {
    if (best[2 * i] + best[2 * i + 1] < best[2 * t] + best[2 * t + 1]) t = i;
  }
  return [for (var i = 0; i < 8; i++) ((best[(2 * t + i) % 8] + 0.5) / (i.isEven ? w : h)).clamp(0.0, 1.0)];
}

/// Shifts [next] cyclically to the labeling closest to [prev], then blends: prev*(1-alpha) + next*alpha.
List<double> smoothQuad(List<double> prev, List<double> next, {double alpha = 0.5}) {
  var k = 0, bestD = double.infinity;
  for (var s = 0; s < 8; s += 2) {
    var d = 0.0;
    for (var j = 0; j < 8; j++) {
      final v = next[(j + s) % 8] - prev[j];
      d += v * v;
    }
    if (d < bestD) {
      bestD = d;
      k = s;
    }
  }
  return [for (var j = 0; j < 8; j++) prev[j] * (1 - alpha) + next[(j + k) % 8] * alpha];
}

Uint8List _blur(Uint8List s, int w, int h) {
  final t = Uint16List(w * h), o = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final r = y * w;
    for (var x = 0; x < w; x++) {
      t[r + x] = s[r + (x < 2 ? 0 : x - 2)] + 4 * s[r + (x < 1 ? 0 : x - 1)] + 6 * s[r + x] +
          4 * s[r + (x + 1 < w ? x + 1 : w - 1)] + s[r + (x + 2 < w ? x + 2 : w - 1)];
    }
  }
  for (var y = 0; y < h; y++) {
    final r0 = (y < 2 ? 0 : y - 2) * w, r1 = (y < 1 ? 0 : y - 1) * w, r = y * w;
    final r3 = (y + 1 < h ? y + 1 : h - 1) * w, r4 = (y + 2 < h ? y + 2 : h - 1) * w;
    for (var x = 0; x < w; x++) {
      o[r + x] = (t[r0 + x] + 4 * t[r1 + x] + 6 * t[r + x] + 4 * t[r3 + x] + t[r4 + x] + 128) >> 8;
    }
  }
  return o;
}

/// L2 magnitude and a direction bin: 0 horizontal, 1 vertical, 2 '\' diagonal, 3 '/' diagonal.
void _sobel(Uint8List b, int w, int h, Float32List mag, Uint8List dir) {
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final a = b[i - w - 1], c = b[i - w + 1], g = b[i + w - 1], k = b[i + w + 1];
      final gx = c + 2 * b[i + 1] + k - a - 2 * b[i - 1] - g, gy = g + 2 * b[i + w] + k - a - 2 * b[i - w] - c;
      mag[i] = math.sqrt(gx * gx + gy * gy);
      final ax = gx.abs(), ay = gy.abs();
      dir[i] = ay * 1000 <= ax * 414 ? 0 : (ay * 1000 >= ax * 2414 ? 1 : ((gx ^ gy) >= 0 ? 2 : 3));
    }
  }
}

double _median(Float32List m, int w, int h) {
  final hist = Int32List(1500);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      hist[m[y * w + x].toInt()]++;
    }
  }
  final half = ((w - 2) * (h - 2) / 2).ceil();
  var acc = 0;
  for (var i = 0; i < hist.length; i++) {
    acc += hist[i];
    if (acc >= half) return i.toDouble();
  }
  return 0;
}

Float32List _nms(Float32List m, Uint8List dir, int w, int h) {
  final o = Float32List(w * h), offs = [1, w, w + 1, w - 1];
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x, v = m[i], off = offs[dir[i]];
      if (v > m[i + off] && v >= m[i - off]) o[i] = v; // asymmetric tie-break: plateaus are not doubled
    }
  }
  return o;
}

Uint8List _hysteresis(Float32List nms, int w, int h, double hi, double lo) {
  final n = w * h, out = Uint8List(n), st = Int32List(n);
  for (var s = 0; s < n; s++) {
    if (out[s] != 0 || nms[s] <= hi) continue;
    out[s] = 1;
    var sp = 0;
    st[sp++] = s;
    while (sp > 0) {
      final p = st[--sp], x = p % w, y = p ~/ w;
      for (var yy = math.max(y - 1, 0); yy <= math.min(y + 1, h - 1); yy++) {
        for (var xx = math.max(x - 1, 0); xx <= math.min(x + 1, w - 1); xx++) {
          final q = yy * w + xx;
          if (out[q] == 0 && nms[q] > lo) {
            out[q] = 1;
            st[sp++] = q;
          }
        }
      }
    }
  }
  return out;
}

Uint8List _dilate(Uint8List s, int w, int h) {
  final t = Uint8List(w * h), o = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final r = y * w;
    for (var x = 0; x < w; x++) {
      t[r + x] = s[r + x] | (x > 0 ? s[r + x - 1] : 0) | (x < w - 1 ? s[r + x + 1] : 0);
    }
  }
  for (var i = 0; i < w * h; i++) {
    o[i] = t[i] | (i >= w ? t[i - w] : 0) | (i < w * h - w ? t[i + w] : 0);
  }
  return o;
}

/// Convex hulls of the large components: edge pixels 8-connected, or non-edge pixels (the sheet interior)
/// 4-connected, since 8-connectivity leaks diagonally through 1 px gaps.
List<List<double>> _hulls(Uint8List e, bool edge, int w, int h) {
  final n = w * h, want = edge ? 1 : 0, seen = Uint8List(n), st = Int32List(n);
  final rowMin = Int32List(h), rowMax = Int32List(h), stamp = Int32List(h);
  final hulls = <List<double>>[];
  var comp = 0;
  for (var s = 0; s < n; s++) {
    if (e[s] != want || seen[s] != 0) continue;
    comp++;
    var sp = 0, minX = w, maxX = -1, minY = h, maxY = -1;
    seen[s] = 1;
    st[sp++] = s;
    while (sp > 0) {
      final p = st[--sp], x = p % w, y = p ~/ w;
      if (stamp[y] != comp) {
        stamp[y] = comp;
        rowMin[y] = rowMax[y] = x;
      } else if (x < rowMin[y]) {
        rowMin[y] = x;
      } else if (x > rowMax[y]) {
        rowMax[y] = x;
      }
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w || (!edge && dx != 0 && dy != 0)) continue;
          final q = yy * w + xx;
          if (e[q] == want && seen[q] == 0) {
            seen[q] = 1;
            st[sp++] = q;
          }
        }
      }
    }
    if ((maxX - minX + 1) * (maxY - minY + 1) < kMinBBoxFrac * n) continue;
    final keys = <int>[];
    for (var y = minY; y <= maxY; y++) {
      if (stamp[y] != comp) continue;
      keys.add(rowMin[y] << 12 | y);
      if (rowMax[y] != rowMin[y]) keys.add(rowMax[y] << 12 | y);
    }
    hulls.add(_hull(keys));
  }
  return hulls;
}

/// Monotone chain over keys x<<12|y. The result has positive shoelace area: TL→TR→BR→BL in image coordinates.
List<double> _hull(List<int> keys) {
  keys.sort();
  final m = keys.length, hx = Int32List(2 * m + 1), hy = Int32List(2 * m + 1);
  var k = 0;
  void add(int key, int lo) {
    final x = key >> 12, y = key & 4095;
    while (k >= lo && (hx[k - 1] - hx[k - 2]) * (y - hy[k - 2]) - (hy[k - 1] - hy[k - 2]) * (x - hx[k - 2]) <= 0) {
      k--;
    }
    hx[k] = x;
    hy[k++] = y;
  }

  for (var i = 0; i < m; i++) {
    add(keys[i], 2);
  }
  final lo = k + 1;
  for (var i = m - 2; i >= 0; i--) {
    add(keys[i], lo);
  }
  return [for (var i = 0; i < k - 1; i++) ...[hx[i].toDouble(), hy[i].toDouble()]];
}

/// Closed Douglas-Peucker with growing epsilon until 4 points, plus the frame-cut fix on the first 5-point result.
List<List<double>> _quads(List<double> hull, int w, int h) {
  final n = hull.length ~/ 2, out = <List<double>>[];
  if (n < 4) return out;
  var per = 0.0;
  for (var i = 0; i < n; i++) {
    per += _dist(hull, i, hull, (i + 1) % n);
  }
  var cut = false;
  for (var eps = kDpMin; eps < kDpMax + kDpStep / 2; eps += kDpStep) {
    final r = _dp(hull, eps * per);
    if (r.length == 10 && !cut) {
      final f = _cutCorner(r, w, h);
      if (f != null) {
        out.add(f);
        cut = true;
      }
    }
    if (r.length <= 8) {
      if (r.length == 8) out.add(r);
      break;
    }
  }
  return out;
}

List<double> _dp(List<double> p, double eps) {
  final n = p.length ~/ 2, keep = Uint8List(n);
  int far(int from) {
    var bi = 0, bd = -1.0;
    for (var i = 0; i < n; i++) {
      final d = _dist(p, from, p, i);
      if (d > bd) {
        bd = d;
        bi = i;
      }
    }
    return bi;
  }

  void rec(int s, int e) {
    final len = (e - s + n) % n, x0 = p[2 * s], y0 = p[2 * s + 1], dx = p[2 * e] - x0, dy = p[2 * e + 1] - y0;
    final l = math.sqrt(dx * dx + dy * dy);
    var bd = -1.0, bi = -1;
    for (var t = 1; t < len; t++) {
      final i = (s + t) % n;
      final d = l == 0 ? _dist(p, s, p, i) : ((p[2 * i] - x0) * dy - (p[2 * i + 1] - y0) * dx).abs() / l;
      if (d > bd) {
        bd = d;
        bi = i;
      }
    }
    if (bd > eps) {
      keep[bi] = 1;
      rec(s, bi);
      rec(bi, e);
    }
  }

  final b = far(0), a = far(b);
  keep[a] = keep[b] = 1;
  rec(a, b);
  rec(b, a);
  return [
    for (var i = 0; i < n; i++)
      if (keep[i] == 1) ...[p[2 * i], p[2 * i + 1]],
  ];
}

/// A 5-gon whose adjacent vertices i, i+1 both lie on the frame border (the same border, or two borders when the
/// corner sticks out past a frame corner): replace them with the intersection of the neighbouring sides, if it is
/// beyond the frame and less than kCutCornerMaxOut outside.
List<double>? _cutCorner(List<double> r, int w, int h) {
  final t = _borderTol(w, h);
  bool near(int i) => r[2 * i] <= t || r[2 * i + 1] <= t || r[2 * i] >= w - 1 - t || r[2 * i + 1] >= h - 1 - t;
  for (var i = 0; i < 5; i++) {
    final j = (i + 1) % 5, k = (i + 2) % 5, l = (i + 3) % 5, p = (i + 4) % 5;
    if (!near(i) || !near(j)) continue;
    final x1 = r[2 * p], y1 = r[2 * p + 1], x2 = r[2 * i], y2 = r[2 * i + 1];
    final x3 = r[2 * k], y3 = r[2 * k + 1], x4 = r[2 * j], y4 = r[2 * j + 1];
    final den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    if (den.abs() < 1e-9) continue;
    final a = x1 * y2 - y1 * x2, b = x3 * y4 - y3 * x4;
    final x = (a * (x3 - x4) - (x1 - x2) * b) / den, y = (a * (y3 - y4) - (y1 - y2) * b) / den;
    const m = kCutCornerMaxOut;
    if ((x < 0 || y < 0 || x > w - 1 || y > h - 1) && x > -m * w && y > -m * h && x < w - 1 + m * w && y < h - 1 + m * h) {
      return [x3, y3, r[2 * l], r[2 * l + 1], x1, y1, x, y];
    }
  }
  return null;
}

double _borderTol(int w, int h) => math.max(kBorderTolPx, kBorderTolFrac * math.max(w, h));

bool _onBorder(double x0, double y0, double x1, double y1, int w, int h) {
  final t = _borderTol(w, h);
  return (x0 <= t && x1 <= t) || (y0 <= t && y1 <= t) || (x0 >= w - 1 - t && x1 >= w - 1 - t) ||
      (y0 >= h - 1 - t && y1 >= h - 1 - t);
}

/// Mean contrast support of the sides off the frame border, or 0 if any side is weak or too many lie on the border.
double _support(Uint8List b, int w, int h, List<double> q) {
  final cx = (q[0] + q[2] + q[4] + q[6]) / 4, cy = (q[1] + q[3] + q[5] + q[7]) / 4;
  var sum = 0.0, cnt = 0, border = 0;
  for (var i = 0; i < 4; i++) {
    final x0 = q[2 * i], y0 = q[2 * i + 1], x1 = q[(2 * i + 2) % 8], y1 = q[(2 * i + 3) % 8];
    if (_onBorder(x0, y0, x1, y1, w, h)) {
      border++;
      continue;
    }
    final len = _dist(q, i, q, (i + 1) % 4), dx = (x1 - x0) / len, dy = (y1 - y0) / len;
    final flip = ((x0 + x1) / 2 - cx) * dy - ((y0 + y1) / 2 - cy) * dx < 0 ? -1 : 1;
    final nx = flip * dy * kSupportOffset, ny = -flip * dx * kSupportOffset; // points away from the centroid
    var pos = 0, neg = 0, tot = 0;
    for (var t = kSupportTrim * len; t <= (1 - kSupportTrim) * len; t++) {
      final px = x0 + dx * t, py = y0 + dy * t;
      final xi = (px - nx).round(), yi = (py - ny).round(), xo = (px + nx).round(), yo = (py + ny).round();
      if (xi < 0 || yi < 0 || xo < 0 || yo < 0 || xi >= w || xo >= w || yi >= h || yo >= h) continue;
      final d = b[yi * w + xi] - b[yo * w + xo];
      tot++;
      if (d >= kMinDiff) {
        pos++;
      } else if (d <= -kMinDiff) {
        neg++;
      }
    }
    if (tot < 8) {
      border++; // mostly outside the frame
      continue;
    }
    final s = math.max(pos, neg) / tot;
    if (s < kMinSideSupport) return 0;
    sum += s;
    cnt++;
  }
  return border > kMaxBorderSides || cnt == 0 ? 0 : sum / cnt;
}

/// Pushes every side of a positive-orientation quad d px outward (miter join).
List<double> _grow(List<double> q, double d) {
  final o = List<double>.filled(8, 0);
  for (var i = 0; i < 4; i++) {
    final p = (i + 3) % 4, n = (i + 1) % 4, la = _dist(q, p, q, i), lb = _dist(q, i, q, n);
    final ax = (q[2 * i] - q[2 * p]) / la, ay = (q[2 * i + 1] - q[2 * p + 1]) / la;
    final bx = (q[2 * n] - q[2 * i]) / lb, by = (q[2 * n + 1] - q[2 * i + 1]) / lb;
    final f = d / (1 + ay * by + ax * bx); // outward normals are (ay, -ax) and (by, -bx)
    o[2 * i] = q[2 * i] + (ay + by) * f;
    o[2 * i + 1] = q[2 * i + 1] - (ax + bx) * f;
  }
  return o;
}

double _area(List<double> q) {
  var a = 0.0;
  for (var i = 0; i < 8; i += 2) {
    a += q[i] * q[(i + 3) % 8] - q[(i + 2) % 8] * q[i + 1];
  }
  return a / 2;
}

double _dist(List<double> p, int i, List<double> q, int j) {
  final dx = q[2 * j] - p[2 * i], dy = q[2 * j + 1] - p[2 * i + 1];
  return math.sqrt(dx * dx + dy * dy);
}
