import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyr/main.dart' show tab;
import 'package:papyr/native.dart' as native;

import 'crop_screen.dart';
import 'session.dart';

// The plugin is a singleton whose dispose unbinds whatever camera is current,
// so every dispose joins this chain and every creation waits for it.
Future<void> _cameraGate = Future.value();
bool _torchOn = false; // lasts while the app lives
final _flashUnits = <String, bool>{}; // camera id -> has a flash unit

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
  String? _err; // CameraException code that stopped the start
  final _thumbs = <String, Future<({Uint8List bytes, int width, int height})>>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop(rebuild: false);
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
        if (!mounted || !_onTop) return;
        if (_err == 'CameraAccessDenied' && !_openedSettings) return; // no dialog loop when denied
        _openedSettings = false;
        _start();
      default:
    }
  }

  bool get _onTop => ModalRoute.of(context)?.isCurrent ?? true;

  void _dispose(CameraController c) => _cameraGate = _cameraGate.then((_) => c.dispose()).catchError((_) {});

  /// Drops the preview from the tree first: building it on a disposed controller throws.
  void _stop({bool rebuild = true}) {
    final c = _c;
    if (c == null) return;
    if (rebuild) {
      setState(() => _c = null);
    } else {
      _c = null;
    }
    _dispose(c);
  }

  Future<void> _start() async {
    if (_c != null || _starting) return;
    _starting = true;
    if (_err != null) setState(() => _err = null);
    CameraController? c;
    try {
      await _cameraGate;
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
      if (!mounted || _background || !_onTop) {
        _dispose(c);
        return;
      }
      setState(() {
        _c = c;
        _hasFlash = hasFlash;
      });
      await c.startImageStream((img) => _onFrame(c!, img));
    } on CameraException catch (e) {
      _fail(c, e.code);
    } catch (e) {
      _fail(c, 'error');
    } finally {
      _starting = false;
    }
  }

  void _fail(CameraController? c, String code) {
    if (identical(c, _c)) {
      if (mounted) _stop();
    } else if (c != null) {
      _dispose(c);
    }
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
  }

  void _retry() {
    _stop();
    _start();
  }

  Future<void> _toggleTorch() async {
    if (!_hasFlash) return;
    setState(() => _torchOn = !_torchOn);
    final c = _c;
    if (c != null) await _setFlash(c, _torchOn ? FlashMode.torch : FlashMode.off);
  }

  /// Camera off (torch and stream too) while the editor and save screens are on top.
  Future<void> _openEditor() async {
    if (_navigating) return;
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
            ColoredBox(color: Colors.black, child: Center(child: CameraPreview(c))),
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
                onPressed: _hasFlash ? _toggleTorch : null,
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
                listenable: session,
                builder: (context, _) {
                  final n = session.photos.length;
                  return FilledButton(
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white38,
                    ),
                    onPressed: n == 0 || _navigating ? null : _openEditor,
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
