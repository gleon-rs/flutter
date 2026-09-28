import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/report/png_info.dart';

void main() {
  test('reads the size from the PNG header and hashes the bytes', () {
    final bytes = File('test/goldens/swatch.png').readAsBytesSync();
    final info = PngInfo.of(bytes);

    expect((info.width, info.height), (100, 60));
    expect(info.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(info.toJson().keys, containsAll(['sha256', 'width', 'height']));
  });

  test('an unreadable header keeps only the hash', () {
    final info = PngInfo.of(Uint8List.fromList(const [1, 2, 3]));

    expect(info.width, isNull);
    expect(info.toJson().keys, ['sha256']);
    expect(
      info.sha256,
      '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
    );
  });
}
