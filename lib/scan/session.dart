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
    notifyListeners();
  }
}
