import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyr/native.dart' as native;

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

  testWidgets('appVersion', (t) async {
    expect(await native.appVersion(), '1.0.0');
  });
}
