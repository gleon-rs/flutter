import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/flutter/case_recorder.dart';

void main() {
  test('the test name is read from the running test', () {
    expect(
      CaseRecorder.currentTestName,
      'the test name is read from the running test',
    );
  });

  test('outside a test there is no test name', () {
    expect(Zone.root.run(() => CaseRecorder.currentTestName), isNull);
  });

  test('the recorded tool version is the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();

    expect(pubspec, contains('version: ${CaseRecorder.packageVersion}'));
  });
}
