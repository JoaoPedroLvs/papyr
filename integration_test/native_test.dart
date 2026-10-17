import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyr/native.dart' as native;
import 'package:papyr/scan/crop_screen.dart' show fullQuad;

final tinyJpeg = base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAABQb/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCKALXj/9k=');

Future<String> twoColorPng() async {
  final r = ui.PictureRecorder();
  ui.Canvas(r)
    ..drawRect(const ui.Rect.fromLTWH(0, 0, 200, 300), ui.Paint()..color = const ui.Color(0xFFFF0000))
    ..drawRect(const ui.Rect.fromLTWH(200, 0, 200, 300), ui.Paint()..color = const ui.Color(0xFF0000FF));
  final img = await r.endRecording().toImage(400, 300);
  final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  return (File('${await native.cacheDir()}/papyr_src.png')..writeAsBytesSync(png)).path;
}

Matcher code(String c) => throwsA(isA<PlatformException>().having((e) => e.code, 'code', c));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('save, list, read, thumbnail, delete round trip', (t) async {
    final tmp = File('${await native.cacheDir()}/papyr_it.jpg')..writeAsBytesSync(tinyJpeg);
    final a = await native.save(tmp.path, 'papyr_it.jpg', 'image/jpeg');
    final b = await native.save(tmp.path, 'papyr_it.jpg', 'image/jpeg');
    final p = await native.save(tmp.path, 'papyr_it.pdf', 'application/pdf');
    final accent = await native.save(tmp.path, 'Recibo São João ${'é' * 90}.jpg', 'image/jpeg');
    expect(a.name, 'papyr_it.jpg');
    expect(b.name, 'papyr_it (1).jpg');
    expect(a.size, tinyJpeg.length);
    expect(accent.name, startsWith('Recibo São João'));
    final items = await native.list();
    expect(items.take(4).map((e) => e.uri), [accent.uri, p.uri, b.uri, a.uri]);
    expect(items[1].isPdf, isTrue);
    expect(await native.read(a.uri), tinyJpeg);
    expect((await native.thumbnail(a.uri, 'image/jpeg', 64)).take(2), [0xFF, 0xD8]);
    for (final x in [a, b, p, accent]) {
      await native.delete(x.uri);
    }
    expect((await native.list()).where((e) => e.uri == a.uri), isEmpty);
    await expectLater(native.delete(a.uri), code('not_found'));
    await expectLater(native.read(a.uri), code('not_found'));
    await expectLater(native.save('/nope/x.jpg', 'x.jpg', 'image/jpeg'), code('not_found'));
    tmp.deleteSync();
  });

  testWidgets('cleanCache removes only CAP*.jpg and papyr_*', (t) async {
    final d = await native.cacheDir();
    final files = [for (final n in ['CAP123.jpg', 'papyr_w_1.jpg', 'papyr_out.pdf', 'keep.txt']) File('$d/$n')..writeAsStringSync('x')];
    await native.cleanCache();
    expect(files.map((f) => f.existsSync()), [false, false, false, true]);
    files.last.deleteSync();
  });

  testWidgets('preview returns upright full size and a downscaled JPEG', (t) async {
    final src = await twoColorPng();
    final p = await native.preview(src, 100);
    expect((p.width, p.height), (400, 300));
    expect(p.bytes.take(2), [0xFF, 0xD8]);
    final f = (await (await ui.instantiateImageCodec(p.bytes)).getNextFrame()).image;
    expect((f.width, f.height), (100, 75));
    await expectLater(native.preview('/nope.jpg', 100), code('not_found'));
  });

  testWidgets('warp crops, rotates clockwise and rejects degenerate corners', (t) async {
    final src = await twoColorPng();
    Future<ui.Image> decode(String p) async =>
        (await (await ui.instantiateImageCodec(File(p).readAsBytesSync())).getNextFrame()).image;
    Future<List<int>> px(ui.Image i, int x, int y) async {
      final b = (await i.toByteData())!;
      final o = (y * i.width + x) * 4;
      return [b.getUint8(o), b.getUint8(o + 1), b.getUint8(o + 2)];
    }
    final full = await native.warp(src, fullQuad, 0);
    expect((full.width, full.height), (400, 300));
    expect(File(full.path).readAsBytesSync().take(2), [0xFF, 0xD8]);
    expect(full.path.split('/').last, startsWith('papyr_w_'));
    final half = await native.warp(src, [0, 0, 0.5, 0, 0.5, 0.5, 0, 0.5], 0);
    expect((half.width, half.height), (200, 150));
    final rot = await native.warp(src, fullQuad, 90);
    expect((rot.width, rot.height), (300, 400));
    final img = await decode(rot.path);
    expect((await px(img, 150, 10))[0], greaterThan(200)); // topo = antiga esquerda (vermelho)
    expect((await px(img, 150, 390))[2], greaterThan(200)); // base = antiga direita (azul)
    await expectLater(native.warp(src, [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], 0), code('decode'));
    await expectLater(native.warp('/nope.jpg', fullQuad, 0), code('not_found'));
  });

  testWidgets('hasFlash reads the camera characteristics', (t) async {
    final back = (await availableCameras()).firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    // This AVD's virtual back camera has no flash unit: enabling the torch fails with "No flash unit".
    expect(await native.hasFlash(back.name), isFalse);
  });

  testWidgets('appVersion', (t) async {
    expect(await native.appVersion(), '1.0.0');
  });
}
