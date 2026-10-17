import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyr/format.dart';
import 'package:papyr/library.dart';
import 'package:papyr/main.dart' show tab;
import 'package:papyr/native.dart' as native;
import 'package:papyr/pdf_writer.dart';

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
  if (mode == SaveMode.pdf) return [await _savePdf(photos, name, onStatus)];
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

/// Page by page, deleting each warped JPEG right after it is appended (disk peak ~2x, not 3x).
Future<String> _savePdf(List<Photo> photos, String name, void Function(String status) onStatus) async {
  final n = photos.length;
  String out;
  try {
    out = '${await native.cacheDir()}/papyr_out.pdf';
  } on PlatformException catch (e) {
    throw SaveError(null, e.code);
  }
  final w = PdfWriter.open(out, pageCount: n);
  int? index = 0;
  try {
    for (var i = 0; i < n; i++) {
      index = i;
      final p = photos[i];
      onStatus('Processando ${i + 1}/$n');
      final tmp = (await native.warp(p.path, p.corners ?? p.detected ?? fullQuad, p.rotation)).path;
      try {
        await w.addPage(tmp);
      } finally {
        await _deleteQuietly(tmp);
      }
    }
    index = null;
    onStatus('Gravando PDF…');
    await w.close();
    return (await native.save(out, '$name.pdf', 'application/pdf')).uri;
  } on PlatformException catch (e) {
    await w.abort();
    throw SaveError(index, e.code);
  } on FormatException {
    await w.abort();
    throw SaveError(index, 'decode');
  } catch (_) {
    await w.abort();
    throw SaveError(index, 'io');
  } finally {
    await _deleteQuietly(out);
  }
}

enum _Stage { editing, processing, done, error }

class SaveScreen extends StatefulWidget {
  const SaveScreen({super.key});

  @override
  State<SaveScreen> createState() => _SaveScreenState();
}

class _SaveScreenState extends State<SaveScreen> {
  final _name = TextEditingController(text: defaultName(DateTime.now()));
  late SaveMode _mode = !_locked && session.photos.length > 1 ? SaveMode.pdf : SaveMode.images;
  _Stage _stage = _Stage.editing;
  String _status = '';
  SaveError? _error;
  List<String> _uris = [];
  String _mime = 'image/jpeg';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// After a partial save in Imagens mode the format can no longer change.
  bool get _locked => session.photos.any((p) => p.savedUri != null);

  Future<void> _save() async {
    final name = sanitizeName(_name.text, defaultName(DateTime.now()));
    setState(() {
      _stage = _Stage.processing;
      _status = '';
    });
    try {
      final uris = await runSave(
        photos: List.of(session.photos),
        name: name,
        mode: _mode,
        onStatus: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      // Ends the session now: its CAP files are gone, so nothing may reopen the editor on them.
      _uris = uris;
      _mime = _mode == SaveMode.pdf ? 'application/pdf' : 'image/jpeg';
      session.clear();
      native.cleanCache();
      if (mounted) setState(() => _stage = _Stage.done);
    } on SaveError catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.error;
          _error = e;
        });
      }
    }
  }

  void _finish() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    tab.value = 0;
    library.refresh();
  }

  String _message(SaveError e) {
    final i = e.index;
    if (i == null) return 'Falha ao gravar o arquivo. Verifique o espaço livre e tente de novo.';
    if (e.code == 'memory') {
      return 'Memória insuficiente para processar a foto ${i + 1}. Volte ao editor, remova essa foto e tente de novo.';
    }
    return 'Falha ao processar a foto ${i + 1}.';
  }

  @override
  Widget build(BuildContext context) {
    final busy = _stage == _Stage.processing || _stage == _Stage.done;
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stage == _Stage.done) _finish();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Salvar'), automaticallyImplyLeading: _stage != _Stage.processing),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: switch (_stage) {
              _Stage.editing => _editing(),
              _Stage.processing => _processing(),
              _Stage.done => _done(),
              _Stage.error => _failed(_error!),
            },
          ),
        ),
      ),
    );
  }

  Widget _editing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Nome'),
        ),
        const SizedBox(height: 16),
        SegmentedButton<SaveMode>(
          segments: const [
            ButtonSegment(value: SaveMode.images, label: Text('Imagens')),
            ButtonSegment(value: SaveMode.pdf, label: Text('PDF')),
          ],
          selected: {_mode},
          onSelectionChanged: _locked ? null : (s) => setState(() => _mode = s.first),
        ),
        const Spacer(),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }

  Widget _processing() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_status),
        ],
      ),
    );
  }

  Widget _done() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Icon(Icons.check_circle_outline, size: 72, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Salvo', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const Spacer(),
        FilledButton.icon(
          onPressed: () => native.share(_uris, _mime),
          icon: const Icon(Icons.share),
          label: const Text('Compartilhar'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _finish, child: const Text('Concluir')),
      ],
    );
  }

  Widget _failed(SaveError e) {
    final saved = [for (final p in session.photos) if (p.savedUri != null) p.savedUri!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Icon(Icons.error_outline, size: 72, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 16),
        Text(_message(e), textAlign: TextAlign.center),
        if (_mode == SaveMode.images && saved.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('${saved.length} de ${session.photos.length} salvas', textAlign: TextAlign.center),
          TextButton.icon(
            onPressed: () => native.share(saved, 'image/jpeg'),
            icon: const Icon(Icons.share),
            label: const Text('Compartilhar'),
          ),
        ],
        const Spacer(),
        FilledButton(onPressed: _save, child: const Text('Tentar de novo')),
      ],
    );
  }
}
