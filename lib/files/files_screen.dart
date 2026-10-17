import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyr/format.dart';
import 'package:papyr/library.dart';
import 'package:papyr/main.dart';
import 'package:papyr/native.dart' as native;

final _thumbs = <String, Uint8List>{};

Future<bool> confirmDelete(BuildContext context, native.MediaItem item) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir arquivo?'),
        content: Text('"${item.name}" será apagado do aparelho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
        ],
      ),
    ) ??
    false;

Future<void> deleteItem(BuildContext context, native.MediaItem item) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await confirmDelete(context, item)) return;
  try {
    await native.delete(item.uri);
  } on PlatformException catch (e) {
    if (e.code != 'not_found') rethrow; // already gone counts as deleted
  }
  await library.refresh();
  messenger.showSnackBar(const SnackBar(content: Text('Arquivo excluído')));
}

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  Widget _message(IconData icon, String text, String action, VoidCallback onPressed) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onPressed, child: Text(action)),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Papyr')),
        body: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            final items = library.items;
            if (items.isEmpty) {
              if (library.loading) return const Center(child: CircularProgressIndicator());
              if (library.error != null) {
                return _message(Icons.error_outline, 'Não foi possível carregar os arquivos.', 'Tentar de novo', library.refresh);
              }
              return _message(Icons.description_outlined, 'Nenhum arquivo ainda', 'Escanear', () => tab.value = 1);
            }
            return RefreshIndicator(
              onRefresh: library.refresh,
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _Row(items[i], key: ValueKey(items[i].uri)),
              ),
            );
          },
        ),
      );
}

class _Row extends StatefulWidget {
  const _Row(this.item, {super.key});

  final native.MediaItem item;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  @override
  void initState() {
    super.initState();
    if (!_thumbs.containsKey(widget.item.uri)) _load();
  }

  Future<void> _load() async {
    final item = widget.item;
    try {
      final bytes = await native.thumbnail(item.uri, item.mime, 192);
      if (mounted) setState(() => _thumbs[item.uri] = bytes);
    } on PlatformException {
      // the grey icon stays
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final thumb = _thumbs[item.uri];
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 56,
          child: thumb == null
              ? ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(item.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined, color: Colors.grey),
                )
              : Image.memory(thumb, fit: BoxFit.cover),
        ),
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(children: [
        DecoratedBox(
          decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(item.isPdf ? 'PDF' : 'IMG',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer)),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text('${formatDate(item.date)} · ${formatSize(item.size)}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) => v == 'share' ? native.share([item.uri], item.mime) : deleteItem(context, item),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'share', child: Text('Compartilhar')),
          PopupMenuItem(value: 'delete', child: Text('Excluir')),
        ],
      ),
    );
  }
}
