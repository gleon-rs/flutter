import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/golden_tolerance.dart';
import 'package:gleon/src/core/compare/pixel_region.dart';
import 'package:gleon/src/core/config/gleon_session.dart';
import 'package:gleon/src/core/native/native_engine.dart';
import 'package:gleon/src/core/native/native_outcome.dart';

void main() {
  test('a library of another ABI is refused with an actionable error', () {
    expect(
      () => NativeEngine.checkAbiVersion(NativeEngine.expectedAbiVersion),
      returnsNormally,
    );
    expect(
      () => NativeEngine.checkAbiVersion(NativeEngine.expectedAbiVersion - 1),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Rebuild the native library'),
        ),
      ),
    );
  });

  test('a missing native library is reported with what to do', () {
    expect(NativeEngine.loadAbiVersion(() => 6), 6);
    expect(
      () => NativeEngine.loadAbiVersion(
        () => throw ArgumentError("Couldn't resolve native function"),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('native library was not loaded'),
            contains('ffi_path'),
          ),
        ),
      ),
    );
  });

  test('verdict codes follow gleon-ffi, unknown codes are errors', () {
    expect(NativeVerdict.of(0), NativeVerdict.identical);
    expect(NativeVerdict.of(6), NativeVerdict.missing);
    expect(NativeVerdict.of(7), NativeVerdict.error);
    expect(NativeVerdict.of(-1), NativeVerdict.error);
    expect(
      [
        for (final verdict in NativeVerdict.values)
          if (verdict.isPass) verdict,
      ],
      [NativeVerdict.identical, NativeVerdict.match, NativeVerdict.updated],
    );
  });

  test('only contract breaches and panics are bugs of gleon', () {
    expect(
      [
        for (final kind in NativeErrorKind.values)
          if (kind.isBug) kind,
      ],
      [NativeErrorKind.internal, NativeErrorKind.invalidInput],
    );
  });

  test('error kind codes follow gleon-ffi, unknown codes are internal', () {
    expect(
      [
        for (final code in [0, 1, 2, 3, 4, 5, 9]) NativeErrorKind.of(code),
      ],
      [
        NativeErrorKind.none,
        NativeErrorKind.invalidInput,
        NativeErrorKind.config,
        NativeErrorKind.io,
        NativeErrorKind.image,
        NativeErrorKind.internal,
        NativeErrorKind.internal,
      ],
    );
  });

  test('invalid session inputs fail every call as invalid input', () {
    final session = GleonSession(
      integration: const GleonIntegration(
        tool: 'gleon_other',
        toolVersion: '1.0.0',
        goldenArtifact: 'expected.png',
        candidateArtifact: '{name}-actual.png',
        diffArtifact: '{name}-diff.png',
      ),
      hasWorkspaces: false,
      environment: const GleonEnvironment(),
    );
    final outcome = NativeEngine.golden(
      session,
      goldenPath: 'a.png',
      goldenUri: 'a.png',
      failuresDir: 'failures/',
      candidate: Uint8List(0),
    );

    expect(outcome.verdict, NativeVerdict.error);
    expect(outcome.errorKind, NativeErrorKind.invalidInput);
    expect(outcome.message, contains('must contain `{name}`'));
  });

  test('the engine writes artifacts named by the integration', () {
    final dir = Directory.systemTemp.createTempSync('gleon_engine_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final golden = File('${dir.path}/a.png')
      ..writeAsBytesSync(File('test/goldens/swatch.png').readAsBytesSync());
    final session = GleonSession(
      integration: const GleonIntegration(
        tool: 'gleon_other',
        toolVersion: '1.0.0',
        goldenArtifact: '{name}-expected.png',
        candidateArtifact: '{name}-actual.png',
        diffArtifact: '{name}-diff.png',
      ),
      hasWorkspaces: false,
      environment: const GleonEnvironment(),
    );
    for (final tolerance in const <GoldenTolerance?>[
      null,
      .exact(),
      .pixel(maxDiffRatio: 0),
      .ssim(minSimilarity: 1, colorTolerance: 0),
    ]) {
      final outcome = NativeEngine.golden(
        session,
        goldenPath: golden.path,
        goldenUri: 'a.png',
        failuresDir: '${dir.path}/failures/',
        candidate: File('test/goldens/blob.png').readAsBytesSync(),
        tolerance: tolerance,
        masks: const [PixelRegion(x: 0, y: 0, width: 1, height: 1)],
      );

      expect(outcome.verdict.isPass, isFalse, reason: '${tolerance ?? 'rule'}');
      expect(outcome.message, startsWith('Golden "a.png": '));
    }
    expect(
      Directory('${dir.path}/failures')
          .listSync()
          .map((file) => file.uri.pathSegments.lastOrNull)
          .toSet(),
      {'a-actual.png', 'a-expected.png'},
      reason: 'different sizes have no diff image',
    );
    final corrupt = NativeEngine.golden(
      session,
      goldenPath: golden.path,
      goldenUri: 'a.png',
      failuresDir: '${dir.path}/failures/',
      candidate: Uint8List(0),
    );

    expect(corrupt.message, contains('could not compare'));
    expect(corrupt.errorKind, NativeErrorKind.image);
  });
}
