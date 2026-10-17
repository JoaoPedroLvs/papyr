import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyr/files/files_screen.dart';
import 'package:papyr/library.dart';
import 'package:papyr/native.dart' as native;

class ImageViewer extends StatefulWidget {
  const ImageViewer(this.item, {super.key});
  final native.MediaItem item;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> with ViewerGone {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  native.MediaItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    native.read(widget.item.uri).then((b) {
      if (mounted) setState(() => _bytes = b);
    }, onError: (Object e) {
      if (!mounted) return;
      if (e is PlatformException && e.code == 'not_found') {
        gone();
      } else {
        setState(() => _failed = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: viewerBar(context, widget.item, delete),
      body: _failed
          ? const Center(child: Text('Não foi possível abrir o arquivo.', style: TextStyle(color: Colors.white)))
          : bytes == null
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(bytes, cacheWidth: 4096))),
    );
  }
}

/// Spec 6.6 for both viewers: when the file vanishes (a failed call, or a list refresh after the
/// gallery deleted it) show the message and close once; the viewer's own delete is not "gone".
mixin ViewerGone<T extends StatefulWidget> on State<T> {
  native.MediaItem get item;
  bool _closed = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    library.addListener(_onLibrary);
  }

  @override
  void dispose() {
    library.removeListener(_onLibrary);
    super.dispose();
  }

  void _onLibrary() {
    if (_deleting || library.loading || library.error != null) return;
    if (!library.items.any((i) => i.uri == item.uri)) gone();
  }

  void gone() {
    if (_closed || !mounted) return;
    _closed = true;
    closeGone(context);
  }

  Future<void> delete() async {
    _deleting = true;
    final deleted = await deleteItem(context, item);
    _deleting = false;
    if (!deleted || _closed || !mounted) return;
    _closed = true;
    closeRoute(context);
  }
}

/// Name, Compartilhar and Excluir; shared by both viewers.
AppBar viewerBar(BuildContext context, native.MediaItem item, VoidCallback onDelete) => AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Compartilhar',
          onPressed: () => native.share([item.uri], item.mime),
          icon: const Icon(Icons.share),
        ),
        IconButton(tooltip: 'Excluir', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
      ],
    );
