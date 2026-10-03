import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import '../core/compare/golden_tolerance.dart';
import '../core/compare/pixel_region.dart';
import '../core/config/gleon_session.dart';
import '../core/native/native_engine.dart';
import '../core/native/native_outcome.dart';
import 'flutter_session.dart';

/// A [GoldenFileComparator] backed by the gleon engine, which resolves the
/// golden's `.gleon/gleon.yaml` rule, compares, and writes failure artifacts,
/// case reports and (`--update-goldens`) the golden itself.
///
/// Golden paths come from the comparator it wraps (normally Flutter's
/// [LocalFileComparator]), so golden files live exactly where they would
/// without this package.
class GleonGoldenComparator extends GoldenFileComparator {
  /// Wraps [delegate]; [tolerance], [masks] and [textTolerance] come from
  /// the matcher call. [session] defaults to [FlutterSession.process].
  GleonGoldenComparator(
    this.delegate, {
    this.tolerance,
    this.masks = const [],
    this.textTolerance,
    GleonSession? session,
  }) : session = session ?? FlutterSession.process;

  /// The comparator that was installed before (owns paths).
  final GoldenFileComparator delegate;

  /// The tolerance of the matcher call; null uses the golden's rule, else
  /// exact.
  final GoldenTolerance? tolerance;

  /// Regions of the matcher call excluded from the comparison, in whole
  /// pixels of the golden.
  final List<PixelRegion> masks;

  /// The text tolerance of the matcher call, a share of a tile (0.0–1.0);
  /// null uses the golden's rule, else 1 (text never fails).
  final double? textTolerance;

  /// Workspace and environment of this process.
  final GleonSession session;

  @override
  Uri getTestUri(Uri key, int? version) => delegate.getTestUri(key, version);

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final local = delegate;
    if (local is LocalFileComparator) {
      _run(local, golden, imageBytes, isUpdate: true);
    } else {
      await local.update(golden, imageBytes);
    }
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    _run(_local, golden, imageBytes);

    return true;
  }

  /// Compares the raw straight RGBA8 [pixels] of a [width] x [height]
  /// capture with [golden]; [textRegions] are the boxes of its text, in
  /// pixels of the capture.
  ///
  /// Throws a [TestFailure] with the engine's message unless it passes.
  void compareRaw(
    Uri golden,
    Uint8List pixels, {
    required int width,
    required int height,
    List<PixelRegion> textRegions = const [],
  }) => _run(
    _local,
    golden,
    pixels,
    rawSize: (height: height, width: width),
    textRegions: textRegions,
  );

  LocalFileComparator get _local => switch (delegate) {
    final LocalFileComparator local => local,
    final other => throw TestFailure(
      'gleon: matchesGoldenFile needs the default LocalFileComparator, but '
      'goldenFileComparator is ${other.runtimeType}. Custom comparators '
      'are not supported yet.',
    ),
  };

  /// One native call; throws a [TestFailure] with the engine's message
  /// unless the golden passes.
  void _run(
    LocalFileComparator local,
    Uri golden,
    Uint8List imageBytes, {
    ({int height, int width})? rawSize,
    List<PixelRegion> textRegions = const [],
    bool isUpdate = false,
  }) {
    final basedir = local.basedir;
    final outcome = NativeEngine.golden(
      session,
      // Same resolution as LocalFileComparator: the key relative to basedir.
      goldenPath: File.fromUri(basedir.resolve(golden.path)).path,
      goldenUri: '$golden',
      failuresDir: Directory.fromUri(basedir.resolve('failures/')).path,
      candidate: imageBytes,
      rawSize: rawSize,
      isUpdate: isUpdate,
      testName: FlutterSession.currentTestName,
      tolerance: tolerance,
      masks: masks,
      textRegions: textRegions,
      textTolerance: textTolerance,
    );
    final NativeOutcome(:console, :errorKind, :message, :verdict, :warning) =
        outcome;
    // One `debugPrint` per line: warnings come newline-separated.
    for (final line in [...warning.split('\n'), console]) {
      if (line.isNotEmpty) debugPrint(line);
    }
    if (!verdict.isPass) {
      throw TestFailure(errorKind.isBug ? '$message\n$bugHint' : message);
    }
  }

  /// Appended to failures that are bugs of gleon, not of the test.
  static const bugHint =
      'This is a bug in gleon, please report it at '
      'https://github.com/gleon-rs/flutter/issues.';
}
