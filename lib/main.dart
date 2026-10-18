import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:papyr/files/files_screen.dart';
import 'package:papyr/library.dart';
import 'package:papyr/native.dart' as native;
import 'package:papyr/scan/camera_screen.dart';
import 'package:papyr/scan/session.dart';
import 'package:papyr/settings_screen.dart';
import 'package:papyr/theme.dart';
import 'package:papyr/widgets/snake_bar.dart';

/// 0 Arquivos, 1 Escanear, 2 Ajustes.
final tab = ValueNotifier<int>(0);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  native.cleanCache().ignore();
  library.refresh();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Newsreader', 'Outfit']) {
      yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/$font-OFL.txt'));
    }
  });
  runApp(const PapyrApp());
}

class PapyrApp extends StatelessWidget {
  const PapyrApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Papyr',
    theme: papyrTheme(Brightness.light),
    darkTheme: papyrTheme(Brightness.dark),
    home: ListenableBuilder(
      listenable: Listenable.merge([tab, session]),
      builder: (context, _) {
        final index = tab.value;
        return PopScope(
          canPop: index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back(context);
          },
          child: Scaffold(
            body: const [FilesScreen(), CameraScreen(), SettingsScreen()][index],
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
        );
      },
    ),
  );

  /// The only root back handler: every PopScope in a route gets the callback, so the discard prompt lives here.
  Future<void> _back(BuildContext context) async {
    final n = session.photos.length;
    if (tab.value != 1 || n == 0) {
      tab.value = 0;
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Descartar $n fotos?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (discard != true) return;
    session.clear();
    native.cleanCache();
    tab.value = 0;
  }
}
