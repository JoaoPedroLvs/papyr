import 'package:flutter/foundation.dart';
import 'package:papyr/native.dart' as native;

final library = Library();

/// MediaStore listing shared by Arquivos and anything that saves or deletes.
/// Concurrent refreshes may overlap; the last response wins.
class Library extends ChangeNotifier {
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
