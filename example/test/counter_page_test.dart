import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:gleon/gleon.dart';

import 'helpers/counter_page_table.dart';

// An alchemist golden test as alchemist users write it: the comparison is
// gleon's (test/flutter_test_config.dart), with the boxes of the text, so the
// golden recorded on macOS passes on every OS of CI.
Future<void> main() async {
  // ignore: missing-test-assertion, goldenTest asserts its golden.
  await goldenTest(
    'counter page',
    fileName: 'counter_page',
    builder: () => const CounterPageTable(),
  );

  // What alchemist does around gleon's assertion, through alchemist's own
  // runner, with goldens in a directory of their own (not this workspace).
  // One run per test: alchemist's wrapper keeps the first pumped route.
  group("alchemist's runner with gleon", () {
    testWidgets('obscured text fails, saying how to compare', (tester) async {
      _goldensDir();
      final message = await _failureOf(tester, isTextObscured: true);

      expect(message, contains('gleon: alchemist obscured the text'));
    });

    testWidgets('a failure says diffThreshold did not apply', (tester) async {
      _goldensDir();
      final message = await _failureOf(tester, threshold: 0.5);

      expect(
        message,
        contains(
          "(AlchemistFileComparator, alchemist's `diffThreshold`) does not "
          'apply',
        ),
      );
      expect(message, isNot(contains('obscured')));
    });

    // Another platform tracks the goldens of this workspace: alchemist's
    // forced update compares instead and writes no golden, failing when the
    // golden would change.
    testWidgets('a forced update elsewhere fails on a change', (tester) async {
      final dir = _goldensDir(isTrackedElsewhere: true);
      final message = await _failureOf(tester, shouldForceUpdate: true);

      expect(message, contains('gleon: the golden was not updated'));
      expect(
        File('${dir.path}/$_golden').readAsBytesSync(),
        File(_otherPage).readAsBytesSync(),
        reason: 'the golden stays',
      );
      expect(_platformDirs(dir), isEmpty);
    });

    testWidgets('a forced update elsewhere passes unchanged', (tester) async {
      final dir = _goldensDir(source: _table, isTrackedElsewhere: true);
      await _run(tester, shouldForceUpdate: true);

      expect(
        File('${dir.path}/$_golden').readAsBytesSync(),
        File(_table).readAsBytesSync(),
        reason: 'text of another OS is ignored: nothing to write',
      );
      expect(_platformDirs(dir), isEmpty);
    });
  });
}

/// The golden of alchemist's runner, relative to its comparator.
const _golden = 'goldens/table.png';

/// A golden of another page, never like the table.
const _otherPage = 'test/goldens/counter_initial.png';

/// The golden of the table (recorded on macOS).
const _table = 'test/goldens/counter_page.png';

/// A directory of goldens for this test, installed as the directory of
/// `goldenFileComparator`, with [source] as [_golden] (by default another
/// page: the table never matches it, whatever the OS). [isTrackedElsewhere]
/// makes it a workspace whose `fallback_platform` is no platform of CI.
Directory _goldensDir({
  String source = _otherPage,
  bool isTrackedElsewhere = false,
}) {
  final dir = Directory.systemTemp.createTempSync('gleon_alchemist_');
  addTearDown(() => dir.deleteSync(recursive: true));
  addTearDown(_restoring(goldenFileComparator));
  goldenFileComparator = LocalFileComparator(dir.uri.resolve('a_test.dart'));
  final golden = File('${dir.path}/$_golden')..parent.createSync();
  File(source).copySync(golden.path);
  if (isTrackedElsewhere) {
    File('${dir.path}/.gleon/gleon.yaml')
      ..parent.createSync()
      ..writeAsStringSync('''
required_version: ">=0.1.0"
fallback_platform: fuchsia-x86_64
screenshots:
  - include: "goldens/*.png"
''');
  }

  return dir;
}

/// The directories beside [_golden] in [dir]: gleon writes none.
List<Directory> _platformDirs(Directory dir) =>
    Directory('${dir.path}/goldens').listSync().whereType<Directory>().toList();

/// Runs alchemist's runner on the counter page table against [_golden].
Future<void> _run(
  WidgetTester tester, {
  bool shouldForceUpdate = false,
  bool isTextObscured = false,
  double threshold = 0,
}) => goldenTestRunner.run(
  tester: tester,
  goldenPath: _golden,
  widget: const CounterPageTable(),
  globalConfigTheme: null,
  variantConfigTheme: null,
  goldenTestTheme: null,
  forceUpdate: shouldForceUpdate,
  obscureText: isTextObscured,
  diffThreshold: threshold,
);

/// The message of the [TestFailure] that [_run] ends with; fails the test if
/// the golden passes.
Future<String> _failureOf(
  WidgetTester tester, {
  bool shouldForceUpdate = false,
  bool isTextObscured = false,
  double threshold = 0,
}) async {
  try {
    await _run(
      tester,
      shouldForceUpdate: shouldForceUpdate,
      isTextObscured: isTextObscured,
      threshold: threshold,
    );
  } on TestFailure catch (error) {
    return error.message ?? fail('a failure without a message');
  }

  return fail('the golden passed');
}

/// Puts [original] back as `goldenFileComparator`.
VoidCallback _restoring(GoldenFileComparator original) =>
    () => goldenFileComparator = original;
