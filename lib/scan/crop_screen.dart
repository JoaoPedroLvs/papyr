import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:papyr/native.dart' as native;

import 'detector.dart';
import 'save_screen.dart';
import 'session.dart';

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

/// Spec 6.4: decodes [jpeg] ([w]x[h] upright) at 320 px on the long side, grays it and detects off the UI isolate.
Future<List<double>?> _detectJpeg(Uint8List jpeg, int w, int h) async {
  final codec = await ui.instantiateImageCodec(jpeg, targetWidth: w >= h ? 320 : null, targetHeight: h > w ? 320 : null);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  final iw = image.width, ih = image.height;
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  image.dispose();
  final gray = Uint8List(iw * ih);
  for (var i = 0; i < gray.length; i++) {
    gray[i] = (rgba[4 * i] * 77 + rgba[4 * i + 1] * 150 + rgba[4 * i + 2] * 29) >> 8;
  }
  return Isolate.run(() => detectQuad(gray, iw, ih));
}

class CropScreen extends StatefulWidget {
  const CropScreen({super.key});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

typedef _Preview = ({Uint8List bytes, int width, int height});

class _CropScreenState extends State<CropScreen> {
  final _pages = PageController();
  final _previews = <Photo, Future<_Preview>>{}; // one decode per photo, shared by its page and the detection
  int _i = 0;
  bool _navigating = false;

  Future<_Preview> _preview(Photo p) => _previews[p] ??= native.preview(p.path, 1600);

  @override
  void initState() {
    super.initState();
    _detectAll();
  }

  /// Spec 6.4: once per photo, every photo of the session (save uses `detected` for pages never shown).
  /// Never touches corners, so a drag made meanwhile wins.
  Future<void> _detectAll() async {
    for (final p in [...session.photos]) {
      if (!mounted) return;
      if (p.detected != null || !session.photos.contains(p)) continue;
      try {
        final img = await _preview(p);
        final q = await _detectJpeg(img.bytes, img.width, img.height);
        if (q == null) continue;
        p.detected = q;
        if (mounted) setState(() {});
      } catch (_) {} // no prefill; a preview failure already shows on its page
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _remove(Photo p) {
    final i = session.photos.indexOf(p);
    if (i < 0) return;
    session.removeAt(i);
    _previews.remove(p);
    if (session.photos.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _i = min(_i, session.photos.length - 1));
  }

  Future<void> _continue() async {
    if (_navigating) return;
    setState(() => _navigating = true);
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SaveScreen()));
    if (mounted) setState(() => _navigating = false);
  }

  @override
  Widget build(BuildContext context) {
    final photos = session.photos;
    if (photos.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final photo = photos[min(_i, photos.length - 1)];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: photos.length > 1 ? Text('${_i + 1} de ${photos.length}') : null,
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: photos.length,
        onPageChanged: (i) => setState(() => _i = i),
        findChildIndexCallback: (key) {
          final i = photos.indexWhere((p) => ObjectKey(p) == key);
          return i < 0 ? null : i;
        },
        itemBuilder: (context, i) => _CropPage(
          key: ObjectKey(photos[i]),
          photo: photos[i],
          preview: _preview(photos[i]),
          onChanged: () => setState(() {}),
          onRemove: () => _remove(photos[i]),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => setState(() => photo.rotation = (photo.rotation + 90) % 360),
                icon: const Icon(Icons.rotate_right),
                label: const Text('Girar 90°'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => setState(() => photo.corners = null),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Redefinir'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => _remove(photo),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover foto'),
              ),
              FilledButton(onPressed: _navigating ? null : _continue, child: const Text('Continuar')),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPage extends StatefulWidget {
  const _CropPage({super.key, required this.photo, required this.preview, required this.onChanged, required this.onRemove});
  final Photo photo;
  final Future<_Preview> preview;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<_CropPage> with AutomaticKeepAliveClientMixin {
  static const _inset = 24.0;
  static const _grabRadius = 48.0;

  Rect _rect = Rect.zero; // image rect in upright (child) space
  int? _drag; // corner index being dragged
  Offset _grab = Offset.zero; // corner minus finger at drag start

  @override
  bool get wantKeepAlive => true;

  List<double> get _quad => widget.photo.corners ?? widget.photo.detected ?? fullQuad;

  Offset _corner(List<double> q, int k) => Offset(_rect.left + q[2 * k] * _rect.width, _rect.top + q[2 * k + 1] * _rect.height);

  int? _nearest(Offset p) {
    final q = _quad;
    int? best;
    var bestD = _grabRadius;
    for (var k = 0; k < 4; k++) {
      final d = (_corner(q, k) - p).distance;
      if (d <= bestD) {
        best = k;
        bestD = d;
      }
    }
    return best;
  }

  void _start(Offset p) {
    final k = _nearest(p);
    if (k == null) return;
    setState(() {
      _drag = k;
      _grab = _corner(_quad, k) - p;
    });
  }

  void _update(Offset p) {
    final k = _drag;
    if (k == null || _rect.isEmpty) return;
    final c = p + _grab;
    final q = [..._quad];
    q[2 * k] = ((c.dx - _rect.left) / _rect.width).clamp(0.0, 1.0);
    q[2 * k + 1] = ((c.dy - _rect.top) / _rect.height).clamp(0.0, 1.0);
    if (!isConvex(q)) return;
    setState(() => widget.photo.corners = q);
  }

  void _end() {
    if (_drag == null) return;
    setState(() => _drag = null);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder(
      future: widget.preview,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não foi possível abrir esta foto.', style: TextStyle(color: Colors.white)),
                const SizedBox(height: 16),
                FilledButton(onPressed: widget.onRemove, child: const Text('Remover')),
              ],
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return LayoutBuilder(builder: (context, box) => _editor(s.data!, box.biggest));
      },
    );
  }

  Widget _editor(_Preview img, Size outer) {
    final turns = widget.photo.rotation ~/ 90;
    final child = turns.isOdd ? outer.flipped : outer; // RotatedBox swaps the axes for its child
    final avail = Rect.fromLTWH(_inset, _inset, max(1, child.width - 2 * _inset), max(1, child.height - 2 * _inset));
    final fitted = applyBoxFit(BoxFit.contain, Size(img.width.toDouble(), img.height.toDouble()), avail.size).destination;
    _rect = Alignment.center.inscribe(fitted, avail);
    final q = _quad;
    final drag = _drag;
    return Stack(
      children: [
        RotatedBox(
          quarterTurns: turns,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _CornerDrag: GestureRecognizerFactoryWithHandlers<_CornerDrag>(
                () => _CornerDrag(),
                (r) => r
                  ..hits = ((p) => _nearest(p) != null)
                  ..onStart = ((d) => _start(d.localPosition))
                  ..onUpdate = ((d) => _update(d.localPosition))
                  ..onEnd = ((_) => _end())
                  ..onCancel = _end,
              ),
            },
            child: SizedBox.fromSize(
              size: child,
              child: Stack(
                children: [
                  Positioned.fromRect(rect: _rect, child: Image.memory(img.bytes, fit: BoxFit.fill, gaplessPlayback: true)),
                  Positioned.fill(child: CustomPaint(painter: _QuadPainter([for (var k = 0; k < 4; k++) _corner(q, k)]))),
                  for (var k = 0; k < 4; k++)
                    Positioned(
                      left: _corner(q, k).dx - _grabRadius / 2,
                      top: _corner(q, k).dy - _grabRadius / 2,
                      child: IgnorePointer(child: _Handle(active: drag == k)),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (drag != null) _magnifier(_toOuter(_corner(q, drag), turns, outer), outer),
      ],
    );
  }

  /// Maps a point in the RotatedBox child's space to the outer box (clockwise quarter turns).
  Offset _toOuter(Offset p, int turns, Size outer) => switch (turns % 4) {
        1 => Offset(outer.width - p.dy, p.dx),
        2 => Offset(outer.width - p.dx, outer.height - p.dy),
        3 => Offset(p.dy, outer.height - p.dx),
        _ => p,
      };

  /// Sits above the corner (below it near the top edge), so the finger never covers it.
  Widget _magnifier(Offset corner, Size outer) {
    const r = 48.0;
    final center = Offset(
      corner.dx.clamp(r, max(r, outer.width - r)),
      corner.dy > 3 * r ? corner.dy - 2 * r : corner.dy + 2 * r,
    );
    return Positioned(
      left: center.dx - r,
      top: center.dy - r,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size(2 * r, 2 * r),
          magnificationScale: 2,
          focalPointOffset: corner - center,
          decoration: const MagnifierDecoration(shape: CircleBorder(side: BorderSide(color: Colors.white, width: 2))),
        ),
      ),
    );
  }
}

/// Claims the pointer at once when it lands on a corner handle, so the PageView swipe never steals it.
class _CornerDrag extends PanGestureRecognizer {
  bool Function(Offset local) hits = (_) => false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!hits(event.localPosition)) return;
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.p);
  final List<Offset> p;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(p, true);
    canvas.drawPath(path, Paint()..color = const Color(0x3300E676));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF00E676),
    );
  }

  @override
  bool shouldRepaint(_QuadPainter o) => true;
}

class _Handle extends StatelessWidget {
  const _Handle({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Center(
        child: Container(
          width: active ? 26 : 22,
          height: active ? 26 : 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.3),
            border: Border.all(color: const Color(0xFF00E676), width: 3),
          ),
        ),
      ),
    );
  }
}
