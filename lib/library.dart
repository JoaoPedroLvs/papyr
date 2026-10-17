import 'package:flutter/widgets.dart';
import 'package:papyr/native.dart' as native;

final library = Library();

/// MediaStore listing shared by Arquivos and anything that saves or deletes.
/// Concurrent refreshes may overlap; the last response wins.
class Library extends ChangeNotifier {
  // App-level, so it also runs when Arquivos is not mounted (spec 6.6: refresh on returning to the app).
  Library() {
    AppLifecycleListener(onResume: refresh);
  }

  List<native.MediaItem> items = [];
  bool loading = false;
  Object? error;

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      items = await native.list();
    } catch (e) {
      error = e;
    }
    loading = false;
    notifyListeners();
  }
}
