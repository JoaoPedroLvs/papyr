import 'package:flutter/material.dart';
import 'package:papyr/files/files_screen.dart';
import 'package:papyr/library.dart';
import 'package:papyr/native.dart' as native;
import 'package:papyr/widgets/snake_bar.dart';

/// 0 Arquivos, 1 Escanear, 2 Ajustes.
final tab = ValueNotifier<int>(0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  native.cleanCache().ignore();
  library.refresh();
  runApp(const PapyrApp());
}

class PapyrApp extends StatelessWidget {
  const PapyrApp({super.key});

  static const _seed = Color(0xFF00897B);

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Papyr',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed)),
        darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark)),
        home: ValueListenableBuilder(
          valueListenable: tab,
          builder: (context, index, _) => PopScope(
            canPop: index == 0,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) tab.value = 0;
            },
            child: Scaffold(
              body: const [FilesScreen(), Center(child: Text('Escanear')), Center(child: Text('Ajustes'))][index],
              bottomNavigationBar: SnakeBar(
                index: index,
                onTap: (i) => tab.value = i,
                items: const [
                  (Icons.folder_outlined, 'Arquivos'),
                  (Icons.document_scanner_outlined, 'Escanear'),
                  (Icons.settings_outlined, 'Ajustes'),
                ],
              ),
            ),
          ),
        ),
      );
}
