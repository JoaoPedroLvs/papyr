import 'package:flutter/services.dart';

/// Typed bridge to MainActivity.kt. Errors arrive as PlatformException with
/// code memory | not_found | decode | io.
const _ch = MethodChannel('papyr/native');

class MediaItem {
  const MediaItem({required this.uri, required this.name, required this.mime, required this.size, required this.date});

  factory MediaItem.fromMap(Map<String, Object?> m) => MediaItem(
        uri: m['uri'] as String,
        name: m['name'] as String,
        mime: m['mime'] as String,
        size: (m['size'] as num).toInt(),
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
      );

  final String uri, name, mime;
  final int size;
  final DateTime date;
  bool get isPdf => mime == 'application/pdf';
}

Map<String, Object?> _map(Object? r) => (r as Map).cast<String, Object?>();

Future<String> cacheDir() async => (await _ch.invokeMethod<String>('cacheDir'))!;

Future<MediaItem> save(String path, String name, String mime) async {
  final r = await _ch.invokeMethod('save', {'path': path, 'name': name, 'mime': mime});
  return MediaItem.fromMap({'mime': mime, ..._map(r)});
}

Future<List<MediaItem>> list() async {
  final r = await _ch.invokeListMethod<Object?>('list');
  return [for (final m in r!) MediaItem.fromMap(_map(m))];
}

Future<void> delete(String uri) => _ch.invokeMethod('delete', {'uri': uri});

Future<Uint8List> read(String uri) async => (await _ch.invokeMethod<Uint8List>('read', {'uri': uri}))!;

/// Downscaled JPEG of a capture plus its upright full-resolution size.
Future<({Uint8List bytes, int width, int height})> preview(String path, int maxSide) async {
  final m = _map(await _ch.invokeMethod('preview', {'path': path, 'maxSide': maxSide}));
  return (bytes: m['bytes'] as Uint8List, width: (m['width'] as num).toInt(), height: (m['height'] as num).toInt());
}

Future<Uint8List> thumbnail(String uri, String mime, int size) async =>
    (await _ch.invokeMethod<Uint8List>('thumbnail', {'uri': uri, 'mime': mime, 'size': size}))!;

Future<void> share(List<String> uris, String mime) => _ch.invokeMethod('share', {'uris': uris, 'mime': mime});

Future<void> openAppSettings() => _ch.invokeMethod('openAppSettings');

Future<String> appVersion() async => (await _ch.invokeMethod<String>('appVersion'))!;

Future<void> cleanCache() => _ch.invokeMethod('cleanCache');
