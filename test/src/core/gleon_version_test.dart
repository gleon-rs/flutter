import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/gleon_version.dart';

void main() {
  test('the recorded tool version is the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();

    expect(pubspec, contains('version: ${GleonVersion.package}'));
  });
}
