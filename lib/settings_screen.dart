import 'package:flutter/material.dart';
import 'package:papyr/format.dart';
import 'package:papyr/library.dart';
import 'package:papyr/native.dart' as native;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ajustes')),
        body: ListView(children: [
          ListenableBuilder(
            listenable: library,
            builder: (context, _) {
              final items = library.items;
              final pdfs = items.where((i) => i.isPdf).length;
              final total = items.fold(0, (s, i) => s + i.size);
              return ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Espaço usado'),
                subtitle: Text('${items.length - pdfs} imagens · $pdfs PDFs · ${formatSize(total)}'),
              );
            },
          ),
          const ListTile(
            leading: Icon(Icons.folder_outlined),
            title: Text('Onde ficam os arquivos'),
            subtitle: Text('Imagens em Pictures/Papyr e PDFs em Documents/Papyr'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Desinstalar o Papyr não apaga seus arquivos, mas eles deixam de aparecer na lista do app.'),
          ),
          FutureBuilder(
            future: native.appVersion(),
            builder: (context, s) => ListTile(
              leading: const Icon(Icons.tag),
              title: const Text('Versão'),
              subtitle: Text(s.data ?? ''),
            ),
          ),
        ]),
      );
}
