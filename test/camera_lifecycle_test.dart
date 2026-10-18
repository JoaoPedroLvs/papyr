import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/main.dart';
import 'package:papyr/scan/camera_screen.dart';
import 'package:papyr/scan/session.dart';
import 'package:papyr/widgets/snake_bar.dart';

import 'fake_camera.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';

void main() {
  late FakeCamera cam;
  final show = ValueNotifier(true);
  final nav = GlobalKey<NavigatorState>();

  // The camera gate is a process-wide future; a future completed in one test's FakeAsync zone never
  // delivers callbacks in the next test's zone, so all scenarios share one testWidgets body.
  void fresh() {
    cam = FakeCamera();
    CameraPlatform.instance = cam;
    show.value = true;
    session.clear();
  }

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('papyr/native'), (c) async {
        if (c.method == 'hasFlash') return true;
        if (c.method == 'preview') throw PlatformException(code: 'decode');
        if (c.method == 'list') return [];
        return null; // cleanCache too
      });
  });

  Future<void> pumpHost(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: show,
          builder: (context, on, _) => on ? const CameraScreen() : const SizedBox(),
        ),
      ),
    ));
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> leave(WidgetTester t) async {
    show.value = false;
    await t.pump();
    // Spec 6.3.1: let the next screen's dispose chain settle before the test ends.
    await settle(t);
  }

  // leaving and re-entering while the camera starts never kills the new camera
  Future<void> reenter(WidgetTester t) async {
    fresh();
    cam.holdInit = Completer<void>();
    final hold = cam.holdInit!;
    await pumpHost(t);
    await t.pump();
    show.value = false; // screen A disposed while its initialize is pending
    await t.pump();
    show.value = true; // screen B
    await settle(t);
    hold.complete();
    await settle(t);
    expect(cam.log, containsAllInOrder(['dispose 1', 'create 2']));
    expect(cam.live, 2);
    expect(find.byKey(const ValueKey('preview 2')), findsOneWidget);
    await leave(t);
  }

  // a start that finishes under a dialog shows the preview once the dialog closes
  Future<void> dialog(WidgetTester t) async {
    fresh();
    cam.holdInit = Completer<void>();
    final hold = cam.holdInit!;
    await pumpHost(t);
    await t.pump();
    showDialog<void>(context: nav.currentContext!, builder: (_) => const AlertDialog(title: Text('Descartar 1 fotos?')));
    await settle(t);
    hold.complete();
    await settle(t);
    nav.currentState!.pop();
    await settle(t);
    expect(find.text('Abrindo câmera…'), findsNothing);
    expect(cam.live, isNotNull);
    expect(find.byKey(ValueKey('preview ${cam.live}')), findsOneWidget);
    await leave(t);
  }

  // Concluir is disabled while a picture is being taken
  Future<void> concluir(WidgetTester t) async {
    fresh();
    session.add(Photo('/c/CAP0.jpg'));
    await pumpHost(t);
    await settle(t);
    cam.holdPicture = Completer<XFile>();
    await t.tap(find.bySemanticsLabel('Tirar foto'));
    await settle(t);
    await t.tap(find.text('Concluir (1)'));
    await settle(t);
    expect(cam.log.where((e) => e.startsWith('dispose')), isEmpty);
    cam.holdPicture!.complete(XFile('/c/CAP1.jpg'));
    await settle(t);
    expect(session.photos, hasLength(2));
    await leave(t);
  }

  // torch taps wait for the pending torch change
  Future<void> torch(WidgetTester t) async {
    fresh();
    await pumpHost(t);
    await settle(t);
    cam.holdFlash = Completer<void>();
    final before = cam.log.length;
    await t.tap(find.byTooltip('Lanterna'));
    await t.pump();
    await t.tap(find.byTooltip('Lanterna'));
    await t.pump();
    expect(cam.log.sublist(before), ['flash torch']);
    cam.holdFlash!.complete();
    cam.holdFlash = null;
    await settle(t);
    await t.tap(find.byTooltip('Lanterna')); // back off, so later tests start with the torch off
    await settle(t);
    expect(cam.log.sublist(before), ['flash torch', 'flash off']);
    await leave(t);
  }

  // the strip counts in Portuguese
  Future<void> count(WidgetTester t) async {
    fresh();
    session.add(Photo('/c/CAP0.jpg'));
    await pumpHost(t);
    await settle(t);
    expect(find.text('1 foto'), findsOneWidget);
    await leave(t);
  }

  // X with no photos goes to Arquivos
  Future<void> close(WidgetTester t) async {
    fresh();
    tab.value = 1;
    await pumpHost(t);
    await settle(t);
    await t.tap(find.byTooltip('Fechar'));
    await settle(t);
    expect(tab.value, 0);
    await leave(t);
  }

  // the shell hides the bar and the scan button on Escanear and brings them back after X
  Future<void> shell(WidgetTester t) async {
    fresh();
    tab.value = 1;
    await t.pumpWidget(const PapyrApp());
    await settle(t);
    expect(find.byType(SnakeBar), findsNothing);
    expect(find.byType(ScanButton), findsNothing);
    await t.tap(find.byTooltip('Fechar'));
    await settle(t);
    expect(find.byType(SnakeBar), findsOneWidget);
    expect(find.byType(ScanButton), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await settle(t); // dispose the camera before the next scenario
  }

  testWidgets('camera lifecycle (spec 6.3, Review Focus 1)', (t) async {
    await reenter(t);
    await dialog(t);
    await concluir(t);
    await torch(t);
    await count(t);
    await close(t);
    await shell(t);
  });
}
