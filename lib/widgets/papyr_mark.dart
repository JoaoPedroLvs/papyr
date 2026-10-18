import 'package:flutter/material.dart';
import 'package:papyr/theme.dart';

/// Height / width of the mark's bracket box (logo.jpeg x 535–1512, y 330–1328).
const double markAspect = 998 / 977;

/// The Papyr mark drawn from the geometry in spec appendix A; [width] is the outer width of the brackets.
/// The glow may paint slightly outside the box.
class PapyrMark extends StatelessWidget {
  const PapyrMark({super.key, required this.width}) : brackets = Brand.sky, sheet = true;

  /// Only the brackets and the glowing scan line, for the Escanear button.
  const PapyrMark.scan({super.key, required this.width, required this.brackets}) : sheet = false;

  final double width;
  final Color brackets;
  final bool sheet;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, width * markAspect), painter: _MarkPainter(brackets, sheet));
}

Path _roundedPolygon(List<Offset> v, double r) {
  final p = Path();
  for (var i = 0; i < v.length; i++) {
    final at = v[i];
    Offset toward(Offset o) => at + (o - at) / (o - at).distance * r;
    final a = toward(v[(i - 1) % v.length]), b = toward(v[(i + 1) % v.length]);
    i == 0 ? p.moveTo(a.dx, a.dy) : p.lineTo(a.dx, a.dy);
    p.quadraticBezierTo(at.dx, at.dy, b.dx, b.dy);
  }
  return p..close();
}

final _bracketPath = () {
  final p = Path();
  for (final (vx, vy, dx, dy) in const [(552.0, 347.0, 1, 1), (1495.0, 347.0, -1, 1), (552.0, 1311.0, 1, -1), (1495.0, 1311.0, -1, -1)]) {
    p
      ..moveTo(vx, vy + dy * 159)
      ..lineTo(vx, vy + dy * 52)
      ..quadraticBezierTo(vx, vy, vx + dx * 52, vy)
      ..lineTo(vx + dx * 159, vy);
  }
  return p;
}();
final _sheetPath = _roundedPolygon(
  const [Offset(850, 405), Offset(1262, 490), Offset(1375, 645), Offset(1225, 1270), Offset(660, 1150)],
  22,
);
final _foldPath = _roundedPolygon(const [Offset(1262, 490), Offset(1240, 622), Offset(1375, 645)], 12);
final _shadowPath = Path()
  ..moveTo(600, 1145)
  ..cubicTo(820, 1180, 1080, 1110, 1310, 955)
  ..lineTo(1400, 1400)
  ..lineTo(560, 1400)
  ..close();

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.brackets, this.sheet);

  final Color brackets;
  final bool sheet;

  @override
  void paint(Canvas canvas, Size size) {
    // Logo units from here on: strokes, radii and the blur sigma are scaled by the canvas, never by hand.
    canvas
      ..scale(size.width / 977)
      ..translate(-535, -330)
      ..drawPath(_bracketPath, _stroke(brackets, 34));
    if (sheet) {
      final white = Paint()..color = Colors.white;
      final outline = _stroke(Brand.navy, 26);
      canvas
        ..drawPath(_sheetPath, white)
        ..save()
        ..clipPath(_sheetPath)
        ..drawPath(_shadowPath, Paint()..color = const Color(0xFFEEF1F8))
        ..restore()
        ..drawPath(_foldPath, white)
        ..drawPath(_sheetPath, outline)
        ..drawPath(_foldPath, outline);
    }
    const line = (Offset(553, 851), Offset(1495, 851));
    canvas
      ..drawLine(
        line.$1,
        line.$2,
        _stroke(Brand.green.withValues(alpha: 0.7), 90)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
      )
      ..drawLine(line.$1, line.$2, _stroke(Brand.green, 34));
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.brackets != brackets || old.sheet != sheet;
}
