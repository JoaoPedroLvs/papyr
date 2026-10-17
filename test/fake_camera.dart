// Test-only: camera_platform_interface is already in the lock file through `camera`; nothing is added to the app.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Models camera_android_camerax's singleton: dispose(id) unbinds whatever camera is live, ignoring the id.
class FakeCamera extends CameraPlatform {
  final log = <String>[];
  int? live;
  Completer<void>? holdInit; // the next initializeCamera waits for it
  Completer<XFile>? holdPicture;
  Completer<void>? holdFlash; // every setFlashMode waits for it while set
  int pending = 0; // setFlashMode calls in flight
  int _next = 0;
  final _ready = <int, StreamController<CameraInitializedEvent>>{};

  StreamController<CameraInitializedEvent> _events(int id) => _ready[id] ??= StreamController.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() async =>
      const [CameraDescription(name: '0', lensDirection: CameraLensDirection.back, sensorOrientation: 90)];

  @override
  Future<int> createCameraWithSettings(CameraDescription description, MediaSettings settings) async {
    final id = ++_next;
    log.add('create $id');
    return id;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) => _events(cameraId).stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => StreamController<CameraErrorEvent>.broadcast().stream; // never fires

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() => const Stream.empty();

  @override
  Future<void> initializeCamera(int cameraId, {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    final hold = holdInit;
    holdInit = null;
    if (hold != null) await hold.future;
    live = cameraId;
    log.add('init $cameraId');
    _events(cameraId).add(CameraInitializedEvent(cameraId, 640, 480, ExposureMode.auto, false, FocusMode.auto, false));
  }

  @override
  Future<void> lockCaptureOrientation(int cameraId, DeviceOrientation orientation) async {}

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    log.add('flash ${mode.name}');
    pending++;
    try {
      final hold = holdFlash;
      if (hold != null) await hold.future;
    } finally {
      pending--;
    }
  }

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(int cameraId, {CameraImageStreamOptions? options}) =>
      const Stream.empty();

  @override
  Future<XFile> takePicture(int cameraId) {
    log.add('shoot');
    return holdPicture?.future ?? Future.value(XFile('/c/CAP${log.length}.jpg'));
  }

  @override
  Widget buildPreview(int cameraId) => SizedBox.expand(key: ValueKey('preview $cameraId'));

  @override
  Future<void> dispose(int cameraId) async {
    log.add('dispose $cameraId');
    live = null;
  }
}
