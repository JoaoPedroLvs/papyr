import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:papyr/format.dart';

void main() {
  test('sanitizeName removes forbidden and control chars, leading dots and spaces', () {
    expect(sanitizeName(r'a/b\c:d*e?f"g<h>i|j', 'X'), 'abcdefghij');
    expect(sanitizeName('a\u0007b\nc', 'X'), 'abc');
    expect(sanitizeName('  . .oculto  ', 'X'), 'oculto');
    expect(sanitizeName('***', 'X'), 'X');
    expect(sanitizeName('   ', 'X'), 'X');
    expect(sanitizeName('Recibo São João', 'X'), 'Recibo São João');
  });

  test('sanitizeName caps the name at 200 UTF-8 bytes without breaking a character', () {
    final r = sanitizeName('😀' * 100, 'X');
    expect(utf8.encode(r).length, lessThanOrEqualTo(200));
    expect(r, '😀' * 50);
    expect(sanitizeName('a' * 100, 'X'), 'a' * 100);
  });

  test('defaultName and formatDate', () {
    expect(defaultName(DateTime(2026, 1, 2, 3, 4, 5)), 'Papyr_20260102_030405');
    expect(formatDate(DateTime(2026, 1, 2, 3, 4)), '02/01/2026 03:04');
  });

  test('formatSize', () {
    expect(formatSize(0), '0 B');
    expect(formatSize(1023), '1023 B');
    expect(formatSize(1536), '1,5 KB');
    expect(formatSize(12897485), '12,3 MB');
    expect(formatSize(3221225472), '3,0 GB');
    expect(formatSize(1048575), '1,0 MB'); // 1023,99 KB must not print as "1024,0 KB"
  });

  test('plural', () {
    expect(plural(1, 'foto', 'fotos'), '1 foto');
    expect(plural(0, 'foto', 'fotos'), '0 fotos');
    expect(plural(12, 'arquivo', 'arquivos'), '12 arquivos');
  });

  test('formatTime', () => expect(formatTime(DateTime(2026, 1, 2, 9, 5)), '09:05'));

  test('formatDay by calendar day (Review Focus 4)', () {
    final now = DateTime(2026, 10, 17, 0, 30);
    expect(formatDay(DateTime(2026, 10, 17, 0, 0), now), 'Hoje');
    expect(formatDay(DateTime(2026, 10, 16, 23, 50), now), 'Ontem');
    expect(formatDay(DateTime(2026, 10, 15, 12), now), '15 de outubro');
    expect(formatDay(DateTime(2026, 3, 1), now), '1 de março');
    expect(formatDay(DateTime(2026, 10, 18, 8), now), '18 de outubro'); // clock skew: never "Hoje"
    final newYear = DateTime(2026, 1, 1, 8);
    expect(formatDay(DateTime(2025, 12, 31, 23, 50), newYear), 'Ontem');
    expect(formatDay(DateTime(2025, 12, 30), newYear), '30 de dezembro de 2025');
  });

  test('storageItems', () {
    expect(storageItems(2, 1), '2 imagens e 1 PDF');
    expect(storageItems(12, 3), '12 imagens e 3 PDFs');
    expect(storageItems(0, 3), '3 PDFs');
    expect(storageItems(1, 0), '1 imagem');
    expect(storageItems(0, 0), isNull);
  });
}
