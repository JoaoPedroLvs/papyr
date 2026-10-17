import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyr/main.dart' show tab;
import 'package:papyr/native.dart' as native;

import 'crop_screen.dart';
import 'detector.dart';
import 'luma.dart';
import 'session.dart';

// The plugin is a singleton whose dispose unbinds whatever camera is current, so each
// creation holds this chain until it is done, and every dispose joins it.
Future<void> _cameraGate = Future.value();
bool _torchOn = false; // lasts while the app lives
final _flashUnits = <String, bool>{}; // camera id -> has a flash unit

/// Sends its port, then answers every (gray, w, h) with detectQuad: a missing reply would leave the camera busy.
void _detectWorker(SendPort out) {
  final rx = ReceivePort();
  out.send(rx.sendPort);
  rx.listen((m) {
    final (gray, w, h) = m as (Uint8List, int, int);
    List<double>? q;
    try {
      q = detectQuad(gray, w, h);
    } catch (_) {}
    out.send(q);
  });
}

/// Spec 6.3.4: EMA over the aligned corners on a hit; the outline goes after 5 misses in a row.
({List<double>? quad, int misses}) trackQuad(List<double>? prev, int misses, List<double>? q) => q != null
    ? (quad: prev == null ? q : smoothQuad(prev, q), misses: 0)
    : (quad: misses + 1 >= 5 ? null : prev, misses: misses + 1);

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _c;
  bool _starting = false;
  bool _background = false;
  bool _openedSettings = false;
  bool _flash = false;
  bool _navigating = false;
  bool _hasFlash = false;
  bool _torchBusy = false;
  String? _err; // CameraException code that stopped the start
  final _thumbs = <String, Future<({Uint8List bytes, int width, int height})>>{};
  final _rx = ReceivePort();
  Isolate? _isolate;
  SendPort? _worker;
  CameraController? _busy; // whose frame the detector has
  List<double>? _quad;
  int _misses = 0;
  bool _loggedSize = false;
  int _replies = 0;
  final _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rx.listen(_onReply);
    Isolate.spawn(_detectWorker, _rx.sendPort).then((i) {
      if (mounted) {
        _isolate = i;
      } else {
        i.kill();
      }
    }, onError: (_) {}); // no worker, no outline
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop(rebuild: false);
    _isolate?.kill();
    _rx.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    switch (s) {
      // Not on inactive: the permission dialog, notification shade and share sheet only cause inactive.
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _background = true;
        _stop();
      case AppLifecycleState.resumed:
        _background = false;
        if (!mounted || _navigating) return; // editor/save on top; a dialog does not count
        if (_err == 'CameraAccessDenied' && !_openedSettings) return; // no dialog loop when denied
        _openedSettings = false;
        _start();
      default:
    }
  }

  void _dispose(CameraController c) => _cameraGate = _cameraGate.then((_) => c.dispose()).catchError((_) {});

  /// Drops the preview from the tree first: building it on a disposed controller throws.
  void _stop({bool rebuild = true}) {
    final c = _c;
    if (c == null) return;
    if (rebuild) {
      setState(() {
        _c = null;
        _quad = null;
      });
    } else {
      _c = null;
      _quad = null;
    }
    _dispose(c);
  }

  Future<void> _start() async {
    if (_c != null || _starting) return;
    _starting = true;
    if (_err != null) setState(() => _err = null);
    final prev = _cameraGate;
    final done = Completer<void>();
    _cameraGate = done.future;
    CameraController? c;
    try {
      await prev;
      final cams = await availableCameras();
      final back = cams.firstWhere((d) => d.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      // Without a flash unit the plugin reports the torch failure as a camera error, not an exception.
      final hasFlash = _flashUnits[back.name] ??= await native.hasFlash(back.name).catchError((_) => false);
      c = CameraController(back, ResolutionPreset.max, enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (hasFlash) {
        // off first, always: the plugin keeps a stale torch flag across controllers.
        await _setFlash(c, FlashMode.off);
        if (_torchOn) await _setFlash(c, FlashMode.torch);
      }
      if (!mounted || _background || _navigating) {
        await _disposeQuietly(c); // inline: this creation still holds the gate
        return;
      }
      setState(() {
        _c = c;
        _hasFlash = hasFlash;
      });
      await c.startImageStream((img) => _onFrame(c!, img));
    } on CameraException catch (e) {
      await _fail(c, e.code);
    } catch (e) {
      await _fail(c, 'error');
    } finally {
      _starting = false;
      done.complete();
    }
  }

  Future<void> _disposeQuietly(CameraController c) async {
    try {
      await c.dispose();
    } catch (_) {
      // already gone
    }
  }

  /// Runs inside the creation, so the dispose is awaited here rather than queued behind the next creation.
  Future<void> _fail(CameraController? c, String code) async {
    if (c != null && identical(c, _c)) {
      if (mounted) {
        setState(() {
          _c = null;
          _quad = null;
        });
      } else {
        _c = null;
      }
    }
    if (c != null) await _disposeQuietly(c);
    if (code == 'CameraPermissionsRequestOngoing' || !mounted) return;
    setState(() => _err = code);
  }

  /// Devices without a flash unit throw; fail silently.
  Future<void> _setFlash(CameraController c, FlashMode m) async {
    try {
      await c.setFlashMode(m);
    } on CameraException {
      // no flash unit
    }
  }

  void _onFrame(CameraController c, CameraImage img) {
    if (!identical(c, _c)) return; // frames can arrive after dispose()
    if (kDebugMode && !_loggedSize) {
      _loggedSize = true;
      debugPrint('analysis ${img.width}x${img.height} vs preview ${c.value.previewSize}');
    }
    final w = _worker;
    if (_busy != null || w == null || c.value.isTakingPicture) return;
    final p = img.planes[0];
    final g = uprightLuma(p.bytes, p.bytesPerRow, img.width, img.height, c.description.sensorOrientation);
    if (g == null) return;
    _busy = c;
    w.send(g);
  }

  void _onReply(Object? m) {
    if (m is SendPort) {
      _worker = m;
      return;
    }
    final c = _busy;
    _busy = null; // always: a stopped controller must not leave it set
    if (kDebugMode && ++_replies % 30 == 0) {
      debugPrint('detector: ${(30e6 / _clock.elapsedMicroseconds).toStringAsFixed(1)} upd/s');
      _clock.reset();
    }
    if (!identical(c, _c)) return; // stopped or replaced while detecting
    final t = trackQuad(_quad, _misses, m as List<double>?);
    _misses = t.misses;
    if (!identical(t.quad, _quad)) setState(() => _quad = t.quad);
  }

  void _retry() {
    _stop();
    _start();
  }

  /// One torch change at a time: overlapping calls race on the plugin's torch flag.
  Future<void> _toggleTorch() async {
    final c = _c;
    if (!_hasFlash || _torchBusy || c == null) return;
    _torchBusy = true;
    setState(() => _torchOn = !_torchOn);
    try {
      await _setFlash(c, _torchOn ? FlashMode.torch : FlashMode.off);
    } finally {
      _torchBusy = false;
    }
  }

  /// Camera off (torch and stream too) while the editor and save screens are on top.
  Future<void> _openEditor() async {
    if (_navigating || (_c?.value.isTakingPicture ?? false)) return; // stopping now would abort the shot
    setState(() => _navigating = true);
    _stop();
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const CropScreen()));
    if (!mounted || tab.value != 1) return; // a finished save already switched to Arquivos
    setState(() => _navigating = false);
    _start();
  }

  Future<void> _shoot() async {
    final c = _c;
    if (c == null || c.value.isTakingPicture) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final x = await c.takePicture();
      session.add(Photo(x.path));
      if (!mounted) return;
      setState(() => _flash = true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (mounted) setState(() => _flash = false);
    } on CameraException {
      messenger.showSnackBar(const SnackBar(content: Text('Falha ao capturar')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: Colors.black,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(child: _preview()),
              _strip(),
              _controls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    if (_err != null) return _error(_err == 'CameraAccessDenied');
    final c = _c;
    if (c == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Abrindo câmera…', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }
    return ValueListenableBuilder<CameraValue>(
      valueListenable: c,
      builder: (context, v, _) {
        if (v.errorDescription != null) return _error(false);
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: Center(child: CameraPreview(c, child: CustomPaint(painter: QuadPainter(_quad)))),
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _flash ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _error(bool denied) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              denied ? 'Sem permissão para usar a câmera.' : 'Não foi possível abrir a câmera.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _retry, child: const Text('Tentar novamente')),
            if (denied)
              TextButton(
                onPressed: () {
                  _openedSettings = true;
                  native.openAppSettings();
                },
                child: const Text('Abrir ajustes'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _strip() {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final photos = session.photos;
        return SizedBox(
          height: 88,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: photos.length,
                  itemBuilder: (context, i) => _thumb(photos[i].path, () => session.removeAt(i)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${photos.length} foto(s)', style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _thumb(String path, VoidCallback onRemove) {
    final f = _thumbs.putIfAbsent(path, () => native.preview(path, 256));
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox.square(
              dimension: 56,
              child: FutureBuilder(
                future: f,
                builder: (context, s) => s.hasData
                    ? Image.memory(s.data!.bytes, fit: BoxFit.cover)
                    : const ColoredBox(color: Colors.white24),
              ),
            ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
              tooltip: 'Remover foto',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    final c = _c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                iconSize: 28,
                color: Colors.white,
                tooltip: 'Lanterna',
                disabledColor: Colors.white24,
                onPressed: _hasFlash && c != null ? _toggleTorch : null,
                icon: Icon(_torchOn && _hasFlash ? Icons.flashlight_on : Icons.flashlight_off),
              ),
            ),
          ),
          if (c == null)
            const _Shutter(onPressed: null)
          else
            ValueListenableBuilder<CameraValue>(
              valueListenable: c,
              builder: (context, v, _) => _Shutter(onPressed: v.isTakingPicture ? null : _shoot),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ListenableBuilder(
                listenable: Listenable.merge([session, ?c]),
                builder: (context, _) {
                  final n = session.photos.length;
                  final shooting = c?.value.isTakingPicture ?? false;
                  return FilledButton(
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white38,
                    ),
                    onPressed: n == 0 || _navigating || shooting ? null : _openEditor,
                    child: Text('Concluir ($n)'),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Tirar foto',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          padding: const EdgeInsets.all(4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onPressed == null ? Colors.white38 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class QuadPainter extends CustomPainter {
  QuadPainter(this.q);
  final List<double>? q; // 8 doubles TL,TR,BR,BL, upright-normalized

  @override
  void paint(Canvas canvas, Size s) {
    final q = this.q;
    if (q == null) return;
    final p = Path()..moveTo(q[0] * s.width, q[1] * s.height);
    for (var i = 2; i < 8; i += 2) {
      p.lineTo(q[i] * s.width, q[i + 1] * s.height);
    }
    canvas.drawPath(
      p..close(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF00E676),
    );
  }

  @override
  bool shouldRepaint(QuadPainter o) => o.q != q;
}
