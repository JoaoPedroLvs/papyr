import 'package:flutter/material.dart';
import 'package:papyr/format.dart';
import 'package:papyr/library.dart';
import 'package:papyr/native.dart' as native;
import 'package:papyr/widgets/papyr_mark.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme, text = theme.textTheme;
    Widget folder(IconData icon, String name, String path) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Icon(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: text.titleMedium),
                Text(path, style: text.bodySmall),
              ]),
            ),
          ]),
        );
    return SafeArea(
      bottom: false,
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          sliver: SliverList.list(children: [
            Text('Ajustes', style: text.headlineLarge),
            const SizedBox(height: 24),
            Text('Espaço usado', style: text.titleSmall),
            const SizedBox(height: 6),
            ListenableBuilder(
              listenable: library,
              builder: (context, _) {
                final items = library.items;
                if (items.isEmpty) return const Text('Nada salvo ainda');
                final pdfs = items.where((i) => i.isPdf);
                final pdfBytes = pdfs.fold(0, (s, i) => s + i.size);
                final total = items.fold(0, (s, i) => s + i.size), imageBytes = total - pdfBytes;
                final kinds = [(scheme.primary, 'Imagens', imageBytes), (scheme.secondary, 'PDFs', pdfBytes)]
                    .where((k) => k.$3 > 0)
                    .toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: formatSize(total), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const TextSpan(text: ' em '),
                    TextSpan(text: storageItems(items.length - pdfs.length, pdfs.length)),
                  ])),
                  const SizedBox(height: 12),
                  ClipRRect(
                    key: const ValueKey('meter'),
                    borderRadius: BorderRadius.circular(4),
                    child: ColoredBox(
                      color: scheme.surfaceContainerHigh,
                      child: SizedBox(
                        height: 8,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          for (final (i, (color, _, bytes)) in kinds.indexed) ...[
                            if (i > 0) const SizedBox(width: 2),
                            Expanded(flex: bytes, child: ColoredBox(color: color)),
                          ],
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 16, runSpacing: 4, children: [
                    for (final (color, label, bytes) in kinds)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox.square(dimension: 8, child: ColoredBox(color: color)),
                        const SizedBox(width: 6),
                        Flexible(child: Text('$label ${formatSize(bytes)}', style: text.bodySmall)),
                      ]),
                  ]),
                ]);
              },
            ),
            const SizedBox(height: 28),
            Text('Onde ficam os arquivos', style: text.titleSmall),
            const SizedBox(height: 2),
            folder(Icons.image_outlined, 'Imagens', 'Pictures/Papyr'),
            const Divider(height: 1),
            folder(Icons.description_outlined, 'PDFs', 'Documents/Papyr'),
            const SizedBox(height: 20),
            DecoratedBox(
              decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Desinstalar o Papyr não apaga seus arquivos, mas eles deixam de aparecer aqui.',
                      style: text.bodySmall,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            // 18 of air plus the 22 dp the scan button rises into the content, so the centred version stays visible
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              const PapyrMark(width: 32),
              const SizedBox(height: 8),
              // a layer, not Image.color: Impeller drew a hairline at the image edges with the paint filter
              ColorFiltered(
                colorFilter: ColorFilter.mode(scheme.primary, BlendMode.srcIn),
                child: Image.asset('assets/brand/wordmark.png', height: 22, semanticLabel: 'Papyr'),
              ),
              const SizedBox(height: 6),
              FutureBuilder(
                future: native.appVersion(),
                builder: (context, s) => Text(s.hasData ? 'Versão ${s.data}' : '', style: text.bodySmall),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
