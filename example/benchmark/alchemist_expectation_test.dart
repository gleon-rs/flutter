import 'dart:io';

import 'package:alchemist/alchemist.dart';
// Until alchemist exports its golden file expectation (Betterment/alchemist#188).
import 'package:alchemist/src/golden_test_adapter.dart'
    show
        FlutterGoldenTestAdapter,
        GoldenFileExpectation,
        defaultGoldenFileExpectation;
import 'package:bench_press/bench_press.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:gleon/alchemist.dart';
import 'package:gleon/gleon.dart';

import '../test/helpers/counter_page_table.dart';

/// How long the assertion that ends a passing alchemist golden test takes:
/// alchemist's default (`flutter_test`'s `matchesGoldenFile`: capture, PNG
/// encode, then decode and compare in Dart) against gleon's (capture, then
/// raw pixels and the boxes of the text compared in Rust), for the golden of
/// `test/counter_page_test.dart`: the same table, fonts and alchemist wrapper.
///
/// Only passes are measured, the common case of a suite: a failing
/// `flutter_test` comparison is reported to the test by Flutter itself.
///
/// `BENCH_PRESS_ARGS` passes bench_press options, e.g. `--validate` for a
/// quick run that only checks the benchmark works.
const _results = 'build/benchmark/alchemist_expectation.json';

/// The golden, relative to the benchmark's directory.
const _golden = 'goldens/counter_page.png';

/// The environment that would make gleon record reports while measured.
const _gleonEnvironment = [
  'GLEON_METRICS',
  'GLEON_ARTIFACTS_DIR',
  'GLEON_RUN_ID',
];

void main() {
  // Like test/flutter_test_config.dart. Alchemist loads the app's fonts again
  // before its golden tests, which changes nothing: the faces loaded first
  // stay (pinned by the package's test/fonts/roboto_layout_test.dart).
  setUpAll(loadAppFonts);

  testWidgets('alchemist expectation: flutter_test vs gleon', (tester) async {
    final set = _gleonEnvironment.where(
      (name) => Platform.environment[name]?.isNotEmpty ?? false,
    );
    expect(set, isEmpty, reason: 'unset them: gleon would write reports');
    final dir = Directory.systemTemp.createTempSync('gleon_alchemist_bench_');
    addTearDown(() => dir.deleteSync(recursive: true));
    addTearDown(_restoring(goldenFileComparator));
    goldenFileComparator = LocalFileComparator(dir.uri.resolve('bench.dart'));
    // Alchemist's CI goldens draw no shadows; it puts the flag back after.
    // ignore: avoid-unnecessary-local-variable, read before it changes.
    final hadShadowsDisabled = debugDisableShadows;
    debugDisableShadows = true;
    try {
      await _pumpLikeAlchemist(tester);
      await _record();
      await _measureAll(tester);
    } finally {
      debugDisableShadows = hadShadowsDisabled;
    }

    expect(File(_results).existsSync(), isTrue);
  });
}

/// Pumps the counter page table like alchemist's `goldenTest`.
Future<void> _pumpLikeAlchemist(WidgetTester tester) =>
    const FlutterGoldenTestAdapter().pumpGoldenTest(
      tester: tester,
      textScaleFactor: 1,
      constraints: const BoxConstraints(),
      obscureFont: false,
      globalConfigTheme: null,
      variantConfigTheme: null,
      goldenTestTheme: null,
      pumpBeforeTest: onlyPumpAndSettle,
      pumpWidget: onlyPumpWidget,
      widget: const CounterPageTable(),
      rootKey: FlutterGoldenTestAdapter.rootKey,
    );

/// Measures both expectations on the pumped table.
Future<void> _measureAll(WidgetTester tester) async {
  // Text compared exactly too, like the Flutter baseline compares every pixel
  // (without a workspace, gleon would ignore it).
  final gleon = gleonAlchemistExpectation(textTolerance: 0);
  // Both pass first: a measured call that failed would measure another
  // code path.
  await _measure(defaultGoldenFileExpectation);
  await _measure(gleon);

  final size = tester.getSize(_root);
  final pixels = (size.width * size.height).round();
  final matrix = Benchmark.matrix<String>(
    cases: const ['counter_page'],
    name: (name) => name,
    baseline: ('alchemist', (_) => _measure(defaultGoldenFileExpectation)),
    candidates: {'gleon': (_) => _measure(gleon)},
    throughput: (_) => .elements(pixels, unit: 'px'),
    config: const BenchmarkConfig(maxTrials: 30),
  );
  final extra = Platform.environment['BENCH_PRESS_ARGS']?.split(' ');
  await mainBenchmarkMatrix(matrix, [
    ...['--target', 'flutter-test', '--json-output', _results],
    ...?extra?.where((arg) => arg.isNotEmpty),
  ]);
}

/// What alchemist captures.
Finder get _root => find.byKey(FlutterGoldenTestAdapter.rootKey);

/// Puts [original] back as `goldenFileComparator`.
VoidCallback _restoring(GoldenFileComparator original) =>
    () => goldenFileComparator = original;

/// Runs [expectation] for the pumped table and [_golden]; throws unless it
/// passes.
Future<void> _measure(GoldenFileExpectation expectation) async {
  await expectation(_root, _golden)();
}

/// Writes the pumped table as [_golden].
Future<void> _record() async {
  final wasUpdating = ft.autoUpdateGoldenFiles;
  ft.autoUpdateGoldenFiles = true;
  try {
    await expectLater(_root, ft.matchesGoldenFile(_golden));
  } finally {
    ft.autoUpdateGoldenFiles = wasUpdating;
  }
}
