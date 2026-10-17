import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/scan/save_screen.dart';
import 'package:papyr/scan/session.dart';

import 'jpeg_fixtures.dart';

final warpBytes = fakeJpeg(40, 400);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late List<MethodCall> calls;
  late Object? Function(MethodCall c) fail; // devolve um erro para lançar, ou null
  var n = 0;
  var saved = 0;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('papyr_save');
    calls = [];
    saved = 0;
    fail = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('papyr/native'), (c) async {
        calls.add(c);
        final e = fail(c);
        if (e != null) throw e;
        switch (c.method) {
          case 'cacheDir': return dir.path;
          case 'warp':
            final f = File('${dir.path}/papyr_w_${n++}.jpg')..writeAsBytesSync(warpBytes);
            return {'path': f.path, 'width': 40, 'height': 400};
          case 'save':
            return {'uri': 'content://x/${++saved}',
                    'name': c.arguments['name'], 'size': 1, 'date': 0};
        }
        return null;
      });
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<Photo> photos(int k) => [for (var i = 0; i < k; i++) Photo('${dir.path}/CAP$i.jpg')];
  Iterable<String> temps() => dir.listSync().map((f) => f.path.split('/').last).where((s) => s.startsWith('papyr_'));
  List<Object?> names() => calls.where((c) => c.method == 'save').map((c) => c.arguments['name']).toList();

  test('images: one photo saves without suffix', () async {
    final uris = await runSave(photos: photos(1), name: 'Doc', mode: SaveMode.images, onStatus: (_) {});
    expect(names(), ['Doc.jpg']);
    expect(uris, ['content://x/1']);
    expect(temps(), isEmpty);
  });

  test('images: partial failure keeps savedUri and retry resumes without duplicates', () async {
    final ps = photos(3);
    var saves = 0;
    fail = (c) => c.method == 'save' && ++saves == 2 ? PlatformException(code: 'io') : null;
    await expectLater(runSave(photos: ps, name: 'Doc', mode: SaveMode.images, onStatus: (_) {}),
        throwsA(isA<SaveError>().having((e) => e.index, 'index', 1).having((e) => e.code, 'code', 'io')));
    expect(ps.map((p) => p.savedUri), ['content://x/1', null, null]);
    expect(temps(), isEmpty);
    calls.clear();
    final uris = await runSave(photos: ps, name: 'Doc', mode: SaveMode.images, onStatus: (_) {});
    expect(calls.where((c) => c.method == 'warp').length, 2);
    expect(names(), ['Doc_02.jpg', 'Doc_03.jpg']);
    expect(uris, ['content://x/1', 'content://x/2', 'content://x/3']);
  });

  test('memory error from warp reports the photo index', () async {
    fail = (c) => c.method == 'warp' && c.arguments['path'].endsWith('CAP1.jpg') ? PlatformException(code: 'memory') : null;
    await expectLater(runSave(photos: photos(2), name: 'Doc', mode: SaveMode.images, onStatus: (_) {}),
        throwsA(isA<SaveError>().having((e) => e.index, 'index', 1).having((e) => e.code, 'code', 'memory')));
  });

  test('warp receives corners ?? detected ?? full image, and rotation', () async {
    final ps = photos(3);
    ps[0].corners = [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9];
    ps[1].detected = [0.2, 0.2, 0.8, 0.2, 0.8, 0.8, 0.2, 0.8];
    ps[2].rotation = 90;
    await runSave(photos: ps, name: 'Doc', mode: SaveMode.images, onStatus: (_) {});
    final w = calls.where((c) => c.method == 'warp').map((c) => c.arguments).toList();
    expect(w[0]['corners'], ps[0].corners);
    expect(w[1]['corners'], ps[1].detected);
    expect(w[2]['corners'], [0, 0, 1, 0, 1, 1, 0, 1]);
    expect(w[2]['rotation'], 90);
  });

  test('pdf: one file from all photos, status sequence, temps deleted', () async {
    final status = <String>[];
    String? head;
    fail = (c) {
      if (c.method == 'save') head = latin1.decode(File(c.arguments['path']).readAsBytesSync().take(8).toList());
      return null;
    };
    final uris = await runSave(photos: photos(2), name: 'Doc', mode: SaveMode.pdf, onStatus: status.add);
    expect(uris, ['content://x/1']);
    final save = calls.singleWhere((c) => c.method == 'save').arguments;
    expect((save['name'], save['mime']), ('Doc.pdf', 'application/pdf'));
    expect(head, '%PDF-1.4');
    expect(status, ['Processando 1/2', 'Processando 2/2', 'Gravando PDF…']);
    expect(temps(), isEmpty);
  });

  test('pdf: warp failure aborts the writer and leaves nothing behind', () async {
    fail = (c) => c.method == 'warp' && c.arguments['path'].endsWith('CAP1.jpg') ? PlatformException(code: 'decode') : null;
    await expectLater(runSave(photos: photos(2), name: 'Doc', mode: SaveMode.pdf, onStatus: (_) {}),
        throwsA(isA<SaveError>().having((e) => e.index, 'index', 1).having((e) => e.code, 'code', 'decode')));
    expect(temps(), isEmpty);
    expect(calls.where((c) => c.method == 'save'), isEmpty);
  });
}
