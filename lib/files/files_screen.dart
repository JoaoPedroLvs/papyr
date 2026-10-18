import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyr/files/image_viewer.dart';
import 'package:papyr/files/pdf_viewer.dart';
import 'package:papyr/format.dart';
import 'package:papyr/library.dart';
import 'package:papyr/native.dart' as native;
import 'package:papyr/widgets/papyr_mark.dart';

final _thumbs = <String, Uint8List>{};

Future<bool> confirmDelete(BuildContext context, native.MediaItem item) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir arquivo?'),
        content: Text('"${item.name}" será apagado do aparelho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    ) ??
    false;

/// Returns whether the item was deleted (false when the user cancelled).
Future<bool> deleteItem(BuildContext context, native.MediaItem item) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await confirmDelete(context, item)) return false;
  try {
    await native.delete(item.uri);
  } on PlatformException catch (e) {
    if (e.code != 'not_found') rethrow; // already gone counts as deleted
  }
  await library.refresh();
  messenger.showSnackBar(const SnackBar(content: Text('Arquivo excluído')));
  return true;
}

/// A viewer's file vanished (deleted in the gallery, for example): message, close, refresh.
void closeGone(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('O arquivo não existe mais.')));
  closeRoute(context);
  library.refresh();
}

/// Closes the route of [context] even when a dialog sits above it (a plain pop would close the dialog).
void closeRoute(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive) return;
  if (route.isCurrent) {
    Navigator.pop(context);
  } else {
    Navigator.of(context).removeRoute(route);
  }
}

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  /// Empty and error states replace the whole scrollable, header included.
  Widget _message(BuildContext context, String title, List<Widget> below) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(34, 0, 34, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const PapyrMark(width: 120),
          const SizedBox(height: 18),
          Text(title, style: text.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          ...below,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            final items = library.items;
            final theme = Theme.of(context);
            if (items.isEmpty) {
              if (library.loading) return const Center(child: CircularProgressIndicator());
              if (library.error != null) {
                return _message(context, 'Não foi possível carregar os arquivos.', [
                  const SizedBox(height: 12),
                  FilledButton(onPressed: library.refresh, child: const Text('Tentar de novo')),
                ]);
              }
              return _message(context, 'Nada escaneado ainda', [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    'Toque no botão do meio para fotografar sua primeira folha.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              ]);
            }
            // the list comes newest first, so each day is one run under its label
            final now = DateTime.now();
            final rows = <Widget>[];
            String? day;
            for (final item in items) {
              final d = formatDay(item.date, now);
              if (d != day) {
                rows.add(Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                  child: Text(day = d, style: theme.textTheme.titleSmall),
                ));
              }
              rows.add(_Row(item, key: ValueKey(item.uri)));
            }
            return RefreshIndicator(
              onRefresh: library.refresh,
              child: CustomScrollView(slivers: [
                // the bottom 24 keeps the last row clear of the raised Escanear button
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 24),
                  sliver: SliverList.list(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const PapyrMark(width: 30),
                        const SizedBox(height: 14),
                        Text('Seus documentos', style: theme.textTheme.headlineLarge),
                        const SizedBox(height: 4),
                        Text(
                          '${plural(items.length, 'arquivo', 'arquivos')}, '
                          '${formatSize(items.fold(0, (sum, i) => sum + i.size))}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ]),
                    ),
                    ...rows,
                  ]),
                ),
              ]),
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
      // the placeholder stays
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final thumb = _thumbs[item.uri];
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final r = BorderRadius.circular(4);
    return InkWell(
      onTap: () async {
        await Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute<void>(builder: (_) => item.isPdf ? PdfViewer(item) : ImageViewer(item)));
        library.refresh();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(children: [
          Container(
            width: 38,
            height: 52,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: r),
            // in front, so the thumbnail does not cover the outline
            foregroundDecoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: r),
            child: thumb == null
                ? Icon(item.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 18, color: scheme.outline)
                : Image.memory(thumb, fit: BoxFit.cover),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                '${item.isPdf ? 'PDF' : 'Imagem'}, ${formatSize(item.size)}, ${formatTime(item.date)}',
                style: text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => v == 'share' ? native.share([item.uri], item.mime) : deleteItem(context, item),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'share', child: Text('Compartilhar')),
              PopupMenuItem(value: 'delete', child: Text('Excluir', style: TextStyle(color: scheme.error))),
            ],
          ),
        ]),
      ),
    );
  }
}
