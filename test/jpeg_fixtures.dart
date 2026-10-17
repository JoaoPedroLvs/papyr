import 'dart:convert';
import 'dart:typed_data';

/// Real 1x1 baseline RGB JPEG (287 bytes).
final tinyJpeg = base64Decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAABQb/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCKALXj/9k=');

/// Header-only JPEG (SOI, APP0, SOF0, EOI): enough for code that only reads SOF.
Uint8List fakeJpeg(int w, int h, [int comps = 3]) => Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46, //
      0xFF, 0xC0, 0x00, 8 + 3 * comps, 8, h >> 8, h & 255, w >> 8, w & 255, comps,
      for (var c = 1; c <= comps; c++) ...[c, 0x11, 0],
      0xFF, 0xD9,
    ]);
