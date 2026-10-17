import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyr/files/files_screen.dart';
import 'package:papyr/native.dart' as native;

class ImageViewer extends StatefulWidget {
  const ImageViewer(this.item, {super.key});
  final native.MediaItem item;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    native.read(widget.item.uri).then((b) {
      if (mounted) setState(() => _bytes = b);
    }, onError: (Object e) {
      if (!mounted) return;
      if (e is PlatformException && e.code == 'not_found') {
        closeGone(context);
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
      appBar: viewerBar(context, widget.item),
      body: _failed
          ? const Center(child: Text('Não foi possível abrir o arquivo.', style: TextStyle(color: Colors.white)))
          : bytes == null
              ? const Center(child: CircularProgressIndicator())
              : InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(bytes, cacheWidth: 4096))),
    );
  }
}

/// Name, Compartilhar and Excluir; shared by both viewers.
AppBar viewerBar(BuildContext context, native.MediaItem item) => AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Compartilhar',
          onPressed: () => native.share([item.uri], item.mime),
          icon: const Icon(Icons.share),
        ),
        IconButton(
          tooltip: 'Excluir',
          onPressed: () async {
            if (await deleteItem(context, item) && context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
