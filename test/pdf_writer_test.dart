import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/pdf_writer.dart';
import 'jpeg_fixtures.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('papyr_pdf'));
  tearDown(() => dir.deleteSync(recursive: true));
  String put(String n, List<int> b) => (File('${dir.path}/$n')..writeAsBytesSync(b)).path;
  Future<void> write(String out, List<String> jpgs) async {
    final w = PdfWriter.open(out, pageCount: jpgs.length);
    for (final j in jpgs) { await w.addPage(j); }
    await w.close();
  }

  test('jpegInfo reads the SOF marker', () {
    expect(jpegInfo(tinyJpeg), (1, 1, 3));
    expect(jpegInfo(fakeJpeg(40, 400)), (40, 400, 3));
    expect(() => jpegInfo(Uint8List.fromList([0, 1, 2])), throwsFormatException);
  });

  test('writes a structurally valid 3-page PDF', () async {
    final jpgs = [tinyJpeg, fakeJpeg(40, 400), fakeJpeg(64, 48, 1)];
    final out = '${dir.path}/o.pdf';
    await write(out, [for (var i = 0; i < 3; i++) put('p$i.jpg', jpgs[i])]);
    final bytes = File(out).readAsBytesSync();
    final s = latin1.decode(bytes);
    expect(s.startsWith('%PDF-1.4\n%'), isTrue);
    expect(bytes.sublist(10, 14).every((b) => b >= 128), isTrue);
    final sx = int.parse(RegExp(r'startxref\n(\d+)\n%%EOF\n$').firstMatch(s)!.group(1)!);
    final head = RegExp(r'xref\n0 (\d+)\n').matchAsPrefix(s, sx)!;
    final count = int.parse(head.group(1)!);
    expect(count, 3 + 3 * 3);
    final e0 = head.end;
    expect(s.substring(e0, e0 + 20), '0000000000 65535 f \n');
    for (var k = 1; k < count; k++) {
      final e = s.substring(e0 + 20 * k, e0 + 20 * (k + 1));
      expect(RegExp(r'^\d{10} 00000 n \n$').hasMatch(e), isTrue, reason: e);
      expect(s.startsWith('$k 0 obj\n', int.parse(e.substring(0, 10))), isTrue, reason: 'obj $k');
    }
    expect(s.substring(e0 + 20 * count).startsWith('trailer\n<< /Size $count /Root 1 0 R >>'), isTrue);
    for (final m in RegExp(r'/Length (\d+) >>\nstream\n').allMatches(s)) {
      expect(s.startsWith('\nendstream\n', m.end + int.parse(m.group(1)!)), isTrue);
    }
    for (final j in jpgs) {
      final at = s.indexOf(latin1.decode(j));
      expect(at, greaterThan(0));
      expect(s.substring(0, at).endsWith('/Length ${j.length} >>\nstream\n'), isTrue);
    }
    expect(s, contains('/MediaBox [0 0 595.28 5952.80]'));
    expect(s, contains('q 595.28 0 0 5952.80 0 0 cm /Im0 Do Q'));
    expect(s, contains('/Width 40 /Height 400 /ColorSpace /DeviceRGB'));
    expect(s, contains('/Width 64 /Height 48 /ColorSpace /DeviceGray'));
  });

  test('CMYK JPEG throws FormatException and leaves no file', () async {
    final out = '${dir.path}/o.pdf';
    await expectLater(write(out, [put('a.jpg', tinyJpeg), put('b.jpg', fakeJpeg(8, 8, 4))]), throwsFormatException);
    expect(File(out).existsSync(), isFalse);
  });

  test('missing input JPEG throws FileSystemException and leaves no file', () async {
    final out = '${dir.path}/o.pdf';
    await expectLater(write(out, ['${dir.path}/nope.jpg']), throwsA(isA<FileSystemException>()));
    expect(File(out).existsSync(), isFalse);
  });

  test('missing output directory throws FileSystemException', () async {
    await expectLater(write('${dir.path}/no/such/o.pdf', [put('a.jpg', tinyJpeg)]), throwsA(isA<FileSystemException>()));
  });

  test('close with fewer pages than declared throws StateError and leaves no file', () async {
    final out = '${dir.path}/o.pdf';
    final w = PdfWriter.open(out, pageCount: 2);
    await w.addPage(put('a.jpg', tinyJpeg));
    await expectLater(w.close(), throwsStateError);
    expect(File(out).existsSync(), isFalse);
  });
}
