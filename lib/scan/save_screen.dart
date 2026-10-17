import 'dart:io';

import 'package:flutter/services.dart';
import 'package:papyr/native.dart' as native;

import 'crop_screen.dart';
import 'session.dart';

enum SaveMode { images, pdf }

class SaveError implements Exception {
  SaveError(this.index, this.code);
  final int? index; // foto que falhou (0-based); null = etapa final do PDF
  final String code; // memory | not_found | decode | io

  @override
  String toString() => 'SaveError($index, $code)';
}

Future<void> _deleteQuietly(String path) async {
  try {
    await File(path).delete();
  } catch (_) {
    // already gone
  }
}

/// Processa as fotos e devolve as URIs salvas (no modo Imagens, inclui as de rodadas anteriores).
Future<List<String>> runSave({
  required List<Photo> photos,
  required String name,
  required SaveMode mode,
  required void Function(String status) onStatus,
}) async {
  if (mode == SaveMode.pdf) throw UnimplementedError();
  final n = photos.length;
  for (var i = 0; i < n; i++) {
    final p = photos[i];
    if (p.savedUri != null) continue;
    onStatus('Processando ${i + 1}/$n');
    String? tmp;
    try {
      tmp = (await native.warp(p.path, p.corners ?? p.detected ?? fullQuad, p.rotation)).path;
      final file = n == 1 ? '$name.jpg' : '${name}_${(i + 1).toString().padLeft(2, '0')}.jpg';
      p.savedUri = (await native.save(tmp, file, 'image/jpeg')).uri;
    } on PlatformException catch (e) {
      throw SaveError(i, e.code);
    } catch (_) {
      throw SaveError(i, 'io');
    } finally {
      if (tmp != null) await _deleteQuietly(tmp);
    }
  }
  return [for (final p in photos) p.savedUri!];
}
