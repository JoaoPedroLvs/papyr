import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyr/files/image_viewer.dart';
import 'package:papyr/native.dart' as native;

class PdfViewer extends StatefulWidget {
  const PdfViewer(this.item, {super.key});
  final native.MediaItem item;

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> with ViewerGone {
  int? _count;
  int _page = 0;
  bool _zoomed = false;
  bool _failed = false;

  @override
  native.MediaItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    native.pdfInfo(widget.item.uri).then((n) {
      if (mounted) setState(() => _count = n);
    }, onError: _onError);
  }

  /// not_found closes the viewer (once); anything else shows the error text.
  void _onError(Object e) {
    if (!mounted) return;
    if (e is PlatformException && e.code == 'not_found') {
      gone();
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _count;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: viewerBar(context, widget.item, delete),
      body: _failed
          ? const Center(child: Text('Não foi possível abrir o arquivo.', style: TextStyle(color: Colors.white)))
          : n == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    PageView.builder(
                      // A zoomed page pans instead of swiping.
                      physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                      itemCount: n,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) => _PdfPage(
                        uri: widget.item.uri,
                        index: i,
                        onZoom: (z) {
                          if (z != _zoomed) setState(() => _zoomed = z);
                        },
                        onError: _onError,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 24,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Text('${_page + 1} / $n', style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _PdfPage extends StatefulWidget {
  const _PdfPage({required this.uri, required this.index, required this.onZoom, required this.onError});
  final String uri;
  final int index;
  final ValueChanged<bool> onZoom;
  final ValueChanged<Object> onError;

  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage> {
  final _tc = TransformationController();
  Uint8List? _bytes;
  bool _failed = false;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _tc.addListener(() => widget.onZoom(_tc.value.getMaxScaleOnAxis() > 1.01));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    final width = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();
    native.pdfPage(widget.uri, widget.index, width).then((b) {
      if (mounted) setState(() => _bytes = b);
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onError(e);
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (_failed) {
      return const Center(child: Text('Não foi possível abrir o arquivo.', style: TextStyle(color: Colors.white)));
    }
    if (bytes == null) return const Center(child: CircularProgressIndicator());
    return InteractiveViewer(
      transformationController: _tc,
      maxScale: 8,
      child: Center(child: Image.memory(bytes, gaplessPlayback: true)),
    );
  }
}
