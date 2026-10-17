import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// (width, height, components) from the JPEG's SOF marker.
(int, int, int) jpegInfo(Uint8List b) {
  if (b.length < 2 || b[0] != 0xFF || b[1] != 0xD8) throw const FormatException('Not a JPEG');
  var i = 2;
  while (i + 9 < b.length && b[i] == 0xFF) {
    final m = b[i + 1];
    if (m == 0xFF) {
      i++; // fill byte
    } else if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
      return (b[i + 7] << 8 | b[i + 8], b[i + 5] << 8 | b[i + 6], b[i + 9]);
    } else {
      i += 2 + (b[i + 2] << 8 | b[i + 3]);
    }
  }
  throw const FormatException('JPEG without SOF');
}

/// Streams one JPEG per page into a PDF 1.4. Objects: 1 Catalog, 2 Pages, then
/// Page/Contents/Image per page, written strictly in order (spec section 8).
class PdfWriter {
  PdfWriter.open(String path, {required this.pageCount}) : _file = File(path) {
    _sink = _file.openWrite()..done.ignore();
    _sink.add(const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A, 0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    _pos = 15;
    _obj('<< /Type /Catalog /Pages 2 0 R >>');
    _obj('<< /Type /Pages /Kids [${[for (var i = 0; i < pageCount; i++) '${3 + 3 * i} 0 R'].join(' ')}] /Count $pageCount >>');
  }

  final int pageCount;
  final File _file;
  late final IOSink _sink;
  final _offsets = <int>[];
  int _pos = 0;

  void _text(String s) {
    _sink.add(ascii.encode(s));
    _pos += s.length;
  }

  void _obj(String dict, [String? stream]) {
    _offsets.add(_pos);
    _text('${_offsets.length} 0 obj\n$dict\n${stream == null ? '' : 'stream\n$stream\nendstream\n'}endobj\n');
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } catch (_) {
      await abort();
      rethrow;
    }
  }

  Future<void> addPage(String jpegPath) => _guard(() async {
        final jpg = File(jpegPath);
        final raf = await jpg.open();
        final int len;
        final Uint8List head;
        try {
          len = await raf.length();
          head = await raf.read(65536);
        } finally {
          await raf.close();
        }
        final (w, h, comps) = jpegInfo(head);
        final cs = switch (comps) {
          1 => '/DeviceGray',
          3 => '/DeviceRGB',
          _ => throw FormatException('JPEG with $comps components', jpegPath),
        };
        final n = _offsets.length + 1;
        final hs = (595.28 * h / w).toStringAsFixed(2);
        _obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 $hs] '
            '/Resources << /XObject << /Im0 ${n + 2} 0 R >> >> /Contents ${n + 1} 0 R >>');
        final content = 'q 595.28 0 0 $hs 0 0 cm /Im0 Do Q';
        _obj('<< /Length ${content.length} >>', content);
        _offsets.add(_pos);
        _text('${n + 2} 0 obj\n<< /Type /XObject /Subtype /Image /Width $w /Height $h /ColorSpace $cs '
            '/BitsPerComponent 8 /Filter /DCTDecode /Length $len >>\nstream\n');
        final start = _pos;
        await _sink.addStream(jpg.openRead().map((c) {
          _pos += c.length;
          return c;
        }));
        if (_pos - start != len) throw FileSystemException('JPEG changed while copying', jpegPath);
        _text('\nendstream\nendobj\n');
      });

  Future<void> close() => _guard(() async {
        final count = _offsets.length + 1;
        if (count != 3 + 3 * pageCount) throw StateError('PDF has ${(count - 3) ~/ 3} of $pageCount pages');
        final xref = _pos;
        _text('xref\n0 $count\n0000000000 65535 f \n'
            '${_offsets.map((o) => '${o.toString().padLeft(10, '0')} 00000 n \n').join()}'
            'trailer\n<< /Size $count /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
        await _sink.close();
      });

  /// Idempotent: closes ignoring errors and deletes the file.
  Future<void> abort() async {
    try {
      await _sink.close();
    } catch (_) {}
    try {
      await _file.delete();
    } catch (_) {}
  }
}
