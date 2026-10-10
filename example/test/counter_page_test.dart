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

      expect(message, contains("alchemist's `diffThreshold` does not apply"));
      expect(message, isNot(contains('obscured')));
    });

    // Another platform's goldens in this workspace: alchemist's forced update
    // writes this platform's own golden beside them, never the shared one.
    testWidgets("a forced update writes this platform's own", (tester) async {
      final dir = _goldensDir();
      Directory('${dir.path}/.gleon').createSync();
      File('${dir.path}/.gleon/gleon.yaml').writeAsStringSync('''
required_version: ">=0.1.0"
fallback_platform: fuchsia-x86_64
screenshots:
  - include: "goldens/*.png"
''');
      await _run(tester, shouldForceUpdate: true);

      expect(
        File('${dir.path}/$_golden').readAsBytesSync(),
        File(_otherPage).readAsBytesSync(),
        reason: 'the shared golden stays',
      );
      final own = Directory('${dir.path}/goldens')
          .listSync()
          .whereType<Directory>()
          .map((platform) => File('${platform.path}/table.png'))
          .where((file) => file.existsSync());
      expect(own, hasLength(1));
    });
  });
}

/// The golden of alchemist's runner, relative to its comparator.
const _golden = 'goldens/table.png';

/// A golden of another page, never like the table.
const _otherPage = 'test/goldens/counter_initial.png';

/// A directory of goldens for this test, installed as the directory of
/// `goldenFileComparator`, with another page as [_golden]: the table never
/// matches it, whatever the OS.
Directory _goldensDir() {
  final dir = Directory.systemTemp.createTempSync('gleon_alchemist_');
  addTearDown(() => dir.deleteSync(recursive: true));
  addTearDown(_restoring(goldenFileComparator));
  goldenFileComparator = LocalFileComparator(dir.uri.resolve('a_test.dart'));
  final golden = File('${dir.path}/$_golden')..parent.createSync();
  File(_otherPage).copySync(golden.path);

  return dir;
}

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
  bool isTextObscured = false,
  double threshold = 0,
}) async {
  try {
    await _run(tester, isTextObscured: isTextObscured, threshold: threshold);
  } on TestFailure catch (error) {
    return error.message ?? fail('a failure without a message');
  }

  return fail('the golden passed');
}

/// Puts [original] back as `goldenFileComparator`.
VoidCallback _restoring(GoldenFileComparator original) =>
    () => goldenFileComparator = original;
