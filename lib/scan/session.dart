import 'package:flutter/foundation.dart';

// ponytail: process-lifetime; lost if Android kills the process (CAP files then removed by cleanCache at next cold start)
final session = Session();

class Photo {
  Photo(this.path);
  final String path; // CAP*.jpg in the cache
  List<double>? detected; // 8 doubles TL,TR,BR,BL, upright-normalized; computed once in the editor
  List<double>? corners; // user's edit; null = detected or the whole image
  int rotation = 0; // 0/90/180/270, clockwise
  String? savedUri; // Imagens mode: already saved (resume after a partial failure)
}

class Session extends ChangeNotifier {
  final photos = <Photo>[];
  Future<void> detecting = Future.value(); // the editor's detection pass; saving waits for it
  // What the last Salvar used, so a trip back to the editor after a failure keeps it.
  String? name;
  bool? pdf;

  void add(Photo p) {
    photos.add(p);
    notifyListeners();
  }

  void removeAt(int i) {
    photos.removeAt(i);
    notifyListeners();
  }

  void clear() {
    photos.clear();
    name = null;
    pdf = null;
    notifyListeners();
  }
}
