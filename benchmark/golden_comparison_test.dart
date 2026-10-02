/// How long one golden comparison takes: Flutter's own `LocalFileComparator`
/// (behind `flutter_test`'s `matchesGoldenFile`) against gleon's comparator,
/// which compares in Rust over FFI. Measured where golden tests run, inside
/// `flutter test`, with the same golden file on disk and the same candidate
/// bytes for every variant.
///
/// Scenarios, at a widget size and a phone screen at 1x and 3x:
/// - `identical`: the candidate has the golden's bytes (a passing golden);
///   both sides short-cut on equal bytes.
/// - `samePixels`: other bytes (an extra PNG text chunk), the same pixels:
///   both decode and compare every pixel.
/// - `mismatch`: a small changed area: both compare, render their diff
///   images and write their failure files.
///
/// Variants: `flutter` (the SDK comparator, exact), `gleon` (exact, the
/// drop-in default) and `gleon_ssim` (the tolerant mode, which Flutter does
/// not have).
///
/// A second benchmark measures what a widget golden costs from the captured
/// frame to the verdict (`widget_capture.json`): Flutter encodes the frame as
/// a PNG and compares it (`identical` short-cuts on equal bytes); gleon
/// passes the frame's raw pixels and encodes a PNG only for a failure.
/// Rendering the frame is the same for both and not measured.
///
/// ```sh
/// flutter test benchmark/
/// dart run bench_press report --from-json build/benchmark/golden_comparison.json
/// ```
///
/// `BENCH_PRESS_ARGS` passes bench_press options, e.g. `--validate` for a
/// smoke run or `--trials 30`.
@Timeout.none
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bench_press/bench_press.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/config/gleon_session.dart';
import 'package:gleon/src/flutter/flutter_session.dart';
import 'package:gleon/src/flutter/gleon_golden_comparator.dart';

/// Where the results go, relative to the package root.
const _results = 'build/benchmark/golden_comparison.json';

/// Where the results of widget captures go, relative to the package root.
const _captureResults = 'build/benchmark/widget_capture.json';

/// A golden size; `hasMismatch` is whether the `mismatch` scenario runs.
typedef _Size = ({bool hasMismatch, int height, String label, int width});

/// Golden sizes: a widget, and a phone screen (390x844 points) at 1x and 3x.
///
/// No `mismatch` at 3x: Flutter's failure path takes about 0.4 s there (gleon
/// 25 ms, M3 Max), over bench_press's 200 ms limit for one operation.
const _sizes = <_Size>[
  (hasMismatch: true, height: 300, label: 'widget', width: 400),
  (hasMismatch: true, height: 844, label: 'phone_1x', width: 390),
  (hasMismatch: false, height: 2532, label: 'phone_3x', width: 1170),
];

/// The kind of comparison a case measures.
enum _Scenario {
  identical(isPass: true),
  mismatch(isPass: false),
  samePixels(isPass: true);

  _Scenario({required this.isPass});

  /// Whether the candidate matches the golden.
  final bool isPass;
}

/// One measured widget capture: the golden on disk and the captured frame.
typedef _Capture = ({
  Uri golden,
  Image image,
  String name,
  int pixels,
  _Scenario scenario,
});

/// One measured comparison: the golden on disk and the candidate's bytes.
typedef _Case = ({
  Uint8List candidate,
  Uri golden,
  String name,
  int pixels,
  _Scenario scenario,
});

void main() {
  test('golden comparison: Flutter SDK vs gleon', () async {
    final dir = Directory.systemTemp.createTempSync('gleon_bench_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final flutter = LocalFileComparator(dir.uri.resolve('bench_test.dart'));
    // No workspace and no environment: exact, nothing recorded, like Flutter.
    final session = GleonSession(
      integration: FlutterSession.integration,
      hasWorkspaces: false,
      environment: const GleonEnvironment(),
    );
    final candidates = <String, GoldenFileComparator>{
      'gleon': GleonGoldenComparator(flutter, session: session),
      'gleon_ssim': GleonGoldenComparator(
        flutter,
        tolerance: const .ssim(),
        session: session,
      ),
    };
    final cases = [
      for (final size in _sizes)
        for (final scenario in _Scenario.values)
          if (scenario.isPass || size.hasMismatch)
            await _prepare(dir, size, scenario),
    ];
    // Each variant must end as its scenario expects, and a failure must be a
    // mismatch (it wrote its failure images), not an error: otherwise it would
    // measure another code path. Measured calls must then end the same way.
    final expected = <(String, String), String?>{};
    for (final testCase in cases) {
      for (final MapEntry(key: name, value: comparator) in {
        'flutter': flutter,
        ...candidates,
      }.entries) {
        // Both comparators copy the golden there for a mismatch only.
        final master = File(
          '${dir.path}/failures/${testCase.name}_masterImage.png',
        );
        if (master.existsSync()) master.deleteSync();
        final outcome = await _failureOf(
          comparator,
          testCase.candidate,
          testCase.golden,
        );
        final reason = '$name, ${testCase.name}: ${outcome ?? 'a pass'}';
        expect(outcome == null, testCase.scenario.isPass, reason: reason);
        expect(master.existsSync(), !testCase.scenario.isPass, reason: reason);
        expected[(name, testCase.name)] = outcome;
      }
    }

    final matrix = Benchmark.matrix<_Case>(
      cases: cases,
      name: (testCase) => testCase.name,
      baseline: (
        'flutter',
        (testCase) => _measure(
          flutter,
          testCase,
          expected: expected[('flutter', testCase.name)],
        ),
      ),
      candidates: {
        for (final MapEntry(key: name, value: comparator) in candidates.entries)
          name: (testCase) => _measure(
            comparator,
            testCase,
            expected: expected[(name, testCase.name)],
          ),
      },
      throughput: (testCase) => .elements(testCase.pixels, unit: 'px'),
      // Failure paths write files, which is noisy: more trials are taken
      // while a variant is unstable.
      config: const BenchmarkConfig(maxTrials: 30),
    );
    final extra = Platform.environment['BENCH_PRESS_ARGS']?.split(' ');
    await mainBenchmarkMatrix(matrix, [
      ...['--target', 'flutter-test', '--json-output', _results],
      ...?extra?.where((arg) => arg.isNotEmpty),
    ]);

    expect(File(_results).existsSync(), isTrue);
  });

  test('widget capture to verdict: Flutter SDK vs gleon', () async {
    final dir = Directory.systemTemp.createTempSync('gleon_bench_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final flutter = LocalFileComparator(dir.uri.resolve('bench_test.dart'));
    final gleon = GleonGoldenComparator(
      flutter,
      session: GleonSession(
        integration: FlutterSession.integration,
        hasWorkspaces: false,
        environment: const GleonEnvironment(),
      ),
    );
    final captures = [
      for (final size in _sizes)
        for (final scenario in const [_Scenario.identical, _Scenario.mismatch])
          if (scenario.isPass || size.hasMismatch)
            await _prepareCapture(dir, size, scenario),
    ];
    addTearDown(() => _dispose(captures));
    // As above: each variant must end as its scenario expects, and measured
    // calls the same way.
    final expected = <String, ({String? flutter, String? gleon})>{};
    for (final capture in captures) {
      final verdicts = (
        flutter: await _pngFailureOf(flutter, capture),
        gleon: await _rawFailureOf(gleon, capture),
      );
      for (final outcome in [verdicts.flutter, verdicts.gleon]) {
        expect(
          outcome == null,
          capture.scenario.isPass,
          reason: '${capture.name}: ${outcome ?? 'a pass'}',
        );
      }
      expected[capture.name] = verdicts;
    }

    final matrix = Benchmark.matrix<_Capture>(
      cases: captures,
      name: (capture) => capture.name,
      baseline: (
        'flutter',
        (capture) => _expectOutcome(
          _pngFailureOf(flutter, capture),
          capture,
          expected: expected[capture.name]?.flutter,
        ),
      ),
      candidates: {
        'gleon': (capture) => _expectOutcome(
          _rawFailureOf(gleon, capture),
          capture,
          expected: expected[capture.name]?.gleon,
        ),
      },
      throughput: (capture) => .elements(capture.pixels, unit: 'px'),
      config: const BenchmarkConfig(maxTrials: 30),
    );
    final extra = Platform.environment['BENCH_PRESS_ARGS']?.split(' ');
    await mainBenchmarkMatrix(matrix, [
      ...['--target', 'flutter-test', '--json-output', _captureResults],
      ...?extra?.where((arg) => arg.isNotEmpty),
    ]);

    expect(File(_captureResults).existsSync(), isTrue);
  });
}

/// Throws unless [outcome] of [capture] is [expected], as when it was
/// verified.
Future<void> _expectOutcome(
  Future<String?> outcome,
  _Capture capture, {
  required String? expected,
}) async {
  final actual = await outcome;
  if (actual != expected) {
    throw StateError(
      '${capture.name} ended differently: ${actual ?? 'a pass'}',
    );
  }
}

/// Judges [capture] like Flutter's matcher does: encodes a PNG and compares.
Future<String?> _pngFailureOf(
  LocalFileComparator comparator,
  _Capture capture,
) async {
  final png = await _png(capture.image);

  return await _failureOf(comparator, png, capture.golden);
}

/// Releases the frames of [captures].
void _dispose(List<_Capture> captures) {
  for (final capture in captures) {
    capture.image.dispose();
  }
}

/// Judges the raw pixels of [capture] like gleon's matcher does: the failure
/// message, or null when it passes.
Future<String?> _rawFailureOf(
  GleonGoldenComparator comparator,
  _Capture capture,
) async {
  final Image(:height, :width) = capture.image;
  final pixels = await capture.image.toByteData(format: .rawStraightRgba);
  if (pixels == null) throw StateError('the engine gave no pixels');
  try {
    comparator.compareRaw(
      capture.golden,
      Uint8List.sublistView(pixels),
      width: width,
      height: height,
    );

    return null;
  } on TestFailure catch (error) {
    return error.message ?? '$error';
  }
}

/// Writes the golden of [scenario] at [size] into [dir] and returns the
/// capture to compare with it.
Future<_Capture> _prepareCapture(
  Directory dir,
  _Size size,
  _Scenario scenario,
) async {
  final (:height, :label, :width, hasMismatch: _) = size;
  final name = 'capture_${scenario.name}_${label}_${width}x$height';
  File('${dir.path}/goldens/$name.png')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(await _render(width, height, isChanged: false));

  return (
    golden: Uri.parse('goldens/$name.png'),
    image: await _image(width, height, isChanged: scenario == .mismatch),
    name: name,
    pixels: width * height,
    scenario: scenario,
  );
}

/// The failure message of [comparator] on [candidate] and [golden], or null
/// when it passes.
/// Both comparators throw for a mismatch: gleon a [TestFailure], Flutter a
/// [FlutterError]; anything else is rethrown.
Future<String?> _failureOf(
  GoldenFileComparator comparator,
  Uint8List candidate,
  Uri golden,
) async {
  try {
    await comparator.compare(candidate, golden);

    return null;
  } on Object catch (error) {
    if (error
        case TestFailure(:final String? message) ||
            FlutterError(:final String? message)) {
      // A failure without a message is still a failure, never a pass.
      return message ?? '$error';
    }

    rethrow;
  }
}

/// Runs [comparator] on [testCase] and throws unless it ends with [expected]
/// (a failure message, or null for a pass) like when it was verified.
Future<void> _measure(
  GoldenFileComparator comparator,
  _Case testCase, {
  required String? expected,
}) async {
  final outcome = await _failureOf(
    comparator,
    testCase.candidate,
    testCase.golden,
  );
  if (outcome != expected) {
    throw StateError(
      '${testCase.name} ended differently: ${outcome ?? 'a pass'}',
    );
  }
}

/// Writes the golden of [scenario] at [size] into [dir] and returns its case.
Future<_Case> _prepare(Directory dir, _Size size, _Scenario scenario) async {
  final (:height, :label, :width, hasMismatch: _) = size;
  final name = '${scenario.name}_${label}_${width}x$height';
  final golden = await _render(width, height, isChanged: false);
  File('${dir.path}/goldens/$name.png')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(golden);

  return (
    candidate: switch (scenario) {
      .identical => golden,
      .mismatch => await _render(width, height, isChanged: true),
      .samePixels => _withTextChunk(golden),
    },
    golden: Uri.parse('goldens/$name.png'),
    name: name,
    pixels: width * height,
    scenario: scenario,
  );
}

/// [_image] encoded as a PNG by the engine, as Flutter's matcher does.
Future<Uint8List> _render(
  int width,
  int height, {
  required bool isChanged,
}) async {
  final image = await _image(width, height, isChanged: isChanged);
  try {
    return await _png(image);
  } finally {
    image.dispose();
  }
}

/// [image] encoded as a PNG by the engine, as Flutter's matcher does.
Future<Uint8List> _png(Image image) async {
  final png = await image.toByteData(format: .png);

  return png?.buffer.asUint8List() ??
      (throw StateError('the engine could not encode a PNG'));
}

/// A screen-like frame: a gradient, cards with shadows and rounded corners,
/// circles and text, plus a 12 px square when [isChanged].
Future<Image> _image(int width, int height, {required bool isChanged}) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  final right = width.toDouble();
  final bottom = height.toDouble();
  canvas.drawRect(
    .fromLTWH(0, 0, right, bottom),
    Paint()
      ..shader = Gradient.linear(.zero, Offset(right, bottom), const [
        Color(0xFFE3F2FD),
        Color(0xFFFFF3E0),
      ]),
  );
  final unit = right / 20;
  for (double top = unit; top + unit * 4 < bottom; top += unit * 5) {
    final card = RRect.fromRectAndRadius(
      .fromLTWH(unit, top, right - unit * 2, unit * 4),
      .circular(unit / 2),
    );
    canvas
      ..drawShadow(Path()..addRRect(card), const Color(0xFF000000), 4, false)
      ..drawRRect(card, Paint()..color = const Color(0xFFFFFFFF))
      ..drawCircle(
        Offset(unit * 3, top + unit * 2),
        unit,
        Paint()..color = const Color(0xFF7E57C2),
      );
    final paragraph =
        (ParagraphBuilder(ParagraphStyle(fontSize: unit * 0.8))
              ..pushStyle(TextStyle(color: const Color(0xFF212121)))
              ..addText('Card at $top: title and a longer subtitle line'))
            .build()
          ..layout(ParagraphConstraints(width: right - unit * 7));
    canvas.drawParagraph(paragraph, Offset(unit * 5, top + unit));
  }
  if (isChanged) {
    canvas.drawRect(
      .fromLTWH(right / 2, bottom / 2, 12, 12),
      Paint()..color = const Color(0xFFE53935),
    );
  }

  return recorder.endRecording().toImage(width, height);
}

/// [png] with a `tEXt` chunk after `IHDR`: other bytes, the same pixels.
Uint8List _withTextChunk(Uint8List png) {
  const header = 33; // Signature (8) + IHDR chunk (4 + 4 + 13 + 4).
  final body =
      (BytesBuilder()
            ..add('tEXtSoftware'.codeUnits)
            ..addByte(0)
            ..add('gleon bench'.codeUnits))
          .takeBytes();
  final crc = _crc32(body);

  return (BytesBuilder(copy: false)
        ..add(png.sublist(0, header))
        ..add(_uint32(body.length - 4))
        ..add(body)
        ..add(_uint32(crc))
        ..add(png.sublist(header)))
      .takeBytes();
}

/// [value] as 4 big-endian bytes.
Uint8List _uint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

/// The CRC-32 of a PNG chunk (type and data).
int _crc32(List<int> bytes) {
  const polynomial = 0xEDB88320;
  int crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (int bit = 0; bit < 8; bit += 1) {
      crc = crc.isOdd ? (crc >>> 1) ^ polynomial : crc >>> 1;
    }
  }

  return crc ^ 0xFFFFFFFF;
}
