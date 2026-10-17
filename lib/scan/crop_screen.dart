const fullQuad = <double>[0, 0, 1, 0, 1, 1, 0, 1];

/// [q] is 8 doubles TL,TR,BR,BL. Strictly convex: every turn has the same sign, none collinear.
bool isConvex(List<double> q) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = i * 2, b = (i + 1) % 4 * 2, c = (i + 2) % 4 * 2;
    final cross = (q[b] - q[a]) * (q[c + 1] - q[b + 1]) - (q[b + 1] - q[a + 1]) * (q[c] - q[b]);
    if (cross.abs() <= 1e-9) return false;
    final s = cross > 0 ? 1 : -1;
    if (sign != 0 && s != sign) return false;
    sign = s;
  }
  return true;
}
