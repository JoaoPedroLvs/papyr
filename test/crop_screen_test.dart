import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/scan/crop_screen.dart';

void main() {
  test('isConvex', () {
    expect(isConvex(fullQuad), isTrue);
    expect(isConvex([0.1, 0.2, 0.9, 0.1, 0.8, 0.9, 0.2, 0.8]), isTrue);
    expect(isConvex([0, 0, 1, 1, 1, 0, 0, 1]), isFalse); // gravata-borboleta
    expect(isConvex([0, 0, 1, 0, 0.4, 0.4, 0, 1]), isFalse); // côncavo
    expect(isConvex([0, 0, 0.5, 0, 1, 0, 0, 1]), isFalse); // 3 pontos colineares
  });
}
