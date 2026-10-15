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
          allOf(contains('release_url'), contains('ffi_path')),
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
            contains('app builds for devices'),
            contains('ffi_path'),
          ),
        ),
      ),
    );
  });

  // A library the host's dynamic loader refuses is told apart from one the
  // hook never provided: the advice differs (a supported host, or a build for
  // this one, against a desktop `flutter test`).
  test('a library the host cannot load is reported with its floor', () {
    // As `dart:ffi` words them (the macOS ones taken from a run).
    for (final reason in [
      _glibcTooOld,
      _dependencyDenied,
      _otherArchitecture,
      _notWin32,
    ]) {
      final message = NativeEngine.describeLoadError(ArgumentError(reason));

      expect(
        message,
        startsWith(
          'gleon: the native library could not be loaded on this host',
        ),
      );
      expect(message, contains(reason));
      expect(
        message,
        allOf(
          contains('Ubuntu 26.04'),
          contains('musl'),
          contains('gleon_repo'),
        ),
      );
      expect(message, isNot(contains('app builds for devices')));
    }
    expect(
      NativeEngine.describeLoadError(
        ArgumentError("Couldn't resolve native function"),
      ),
      allOf(contains('was not loaded'), contains('app builds for devices')),
    );
  });

  // A file that is gone (the build output removed after the build) is
  // neither: building it again helps, another host does not.
  test('a library file that is gone asks for a new build', () {
    for (final reason in [_goneMacos, _goneLinux, _goneWindows]) {
      final message = NativeEngine.describeLoadError(ArgumentError(reason));

      expect(message, startsWith('gleon: the native library file is missing'));
      expect(message, allOf(contains(reason), contains('flutter test')));
      expect(message, isNot(contains('musl')));
    }
  });

  // The loaders word a missing dependency like a missing library: the
  // library that is still there points at the host, not at a new build.
  test('a library that is there but lacks a dependency is no gone file', () {
    final dir = Directory.systemTemp.createTempSync('gleon_engine_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final library = File('${dir.path}/libgleon_ffi.so')..createSync();
    final linux =
        "Failed to load dynamic library '${library.path}': libgcc_s.so.1: "
        'cannot open shared object file: No such file or directory';
    final windows =
        "Failed to load dynamic library '${library.path}': "
        'The specified module could not be found. (error code: 126)';
    for (final reason in [linux, windows]) {
      final message = NativeEngine.describeLoadError(ArgumentError(reason));

      expect(
        message,
        startsWith(
          'gleon: the native library could not be loaded on this host: a '
          'library it needs is missing',
        ),
      );
      expect(message, allOf(contains(reason), contains('gleon_repo')));
      expect(message, isNot(contains('removed after the build')));
    }
  });

  test('verdict codes follow gleon-ffi, unknown codes are errors', () {
    // Zero is an error: a summary the library never wrote is no pass.
    expect(NativeVerdict.of(0), NativeVerdict.error);
    expect(NativeVerdict.of(1), NativeVerdict.identical);
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

  test('a disposed session is released once and never used again', () {
    final session = GleonSession(
      integration: const GleonIntegration(
        tool: 'gleon_flutter',
        toolVersion: '0.1.0',
        goldenArtifact: '{name}_masterImage.png',
        candidateArtifact: '{name}_testImage.png',
        diffArtifact: '{name}_gleonDiff.png',
      ),
      hasWorkspaces: false,
      environment: const GleonEnvironment(),
    );
    // A second call does nothing.
    for (int call = 0; call < 2; call += 1) {
      session.dispose();
    }

    expect(session.isDisposed, isTrue);
    expect(
      () => NativeEngine.golden(
        session,
        goldenPath: 'a.png',
        goldenUri: 'a.png',
        failuresDir: 'failures/',
        candidate: Uint8List(0),
      ),
      throwsA(isA<StateError>()),
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
      {'a-actual.png', 'a-expected.png', 'a-diff.png'},
      reason: 'different sizes keep a diff of both',
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

  test('raw candidates must have width x height RGBA pixels', () {
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
    NativeOutcome compare(Uint8List pixels) => NativeEngine.golden(
      session,
      goldenPath: golden.path,
      goldenUri: 'a.png',
      failuresDir: '${dir.path}/failures/',
      candidate: pixels,
      rawSize: (height: 60, width: 100),
      textRegions: const [PixelRegion(x: 0, y: 0, width: 10, height: 10)],
      textTolerance: 0.1,
    );

    final short = compare(Uint8List(100 * 60 * 4 - 1));
    expect(short.errorKind, NativeErrorKind.invalidInput);
    expect(short.message, contains('100x60 RGBA needs 24000'));

    final white = compare(Uint8List(100 * 60 * 4)..fillRange(0, 24000, 255));
    expect(white.verdict, NativeVerdict.mismatch);
    expect(white.message, contains('text ≤ 10.00% per tile'));
    expect(File('${dir.path}/failures/a-actual.png').existsSync(), isTrue);
  });
}

// What `dart:ffi` reports when it cannot load the library.

const _glibcTooOld =
    "Failed to load dynamic library '/x/libgleon_ffi.so': "
    '/lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.43` not found '
    '(required by /x/libgleon_ffi.so)';

const _dependencyDenied =
    "Failed to load dynamic library '/x/libgleon_ffi.so': libgcc_s.so.1: "
    'cannot open shared object file: Permission denied';

const _otherArchitecture =
    "Failed to load dynamic library '/x/libgleon_ffi.dylib': "
    'dlopen(/x/libgleon_ffi.dylib, 0x0001): tried: '
    "'/x/libgleon_ffi.dylib' (mach-o file, but is an incompatible "
    "architecture (have 'arm64', need 'x86_64'))";

const _notWin32 =
    r"Failed to load dynamic library 'C:\x\gleon_ffi.dll': "
    '%1 is not a valid Win32 application. (error code: 193)';

const _goneMacos =
    "Failed to load dynamic library '/x/libgleon_ffi.dylib': "
    'dlopen(/x/libgleon_ffi.dylib, 0x0001): tried: '
    "'/x/libgleon_ffi.dylib' (no such file)";

const _goneLinux =
    "Failed to load dynamic library '/x/libgleon_ffi.so': /x/libgleon_ffi.so: "
    'cannot open shared object file: No such file or directory';

const _goneWindows =
    r"Failed to load dynamic library 'C:\x\gleon_ffi.dll': "
    'The specified module could not be found. (error code: 126)';
