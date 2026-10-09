import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../compare/golden_tolerance.dart';
import '../compare/pixel_region.dart';
import '../config/gleon_session.dart';
import 'gleon_ffi.dart';
import 'native_outcome.dart';

/// The gleon engine behind the native `gleon-ffi` library.
///
/// The engine does the whole job of a golden (rule resolution, comparison,
/// failure artifacts, case reports, updates); this side passes facts and
/// shows the texts it gets back. Calls are synchronous leaf calls (see
/// `gleon_ffi.dart` for why).
abstract final class NativeEngine {
  /// C contract version this Dart code understands (`ABI_VERSION` in
  /// `gleon-ffi`). Keep both in lockstep.
  static const expectedAbiVersion = 11;

  /// Asked once per process, on the first call.
  // ignore: avoid-explicit-type-declaration, not obvious from the initializer.
  static final int _abiVersion = loadAbiVersion(GleonFfi.abiVersion);

  /// `gleon_golden` mode: compare the candidate with the golden.
  static const _compareMode = 0;

  /// `gleon_golden` mode: write the candidate as the golden.
  static const _updateMode = 1;

  /// `gleon_golden` candidate format: PNG bytes.
  static const _pngFormat = 0;

  /// `gleon_golden` candidate format: raw straight RGBA8 pixels.
  static const _rawFormat = 1;

  /// `gleon_session_new` flag: each golden belongs to the nearest directory
  /// above it with `.gleon/gleon.yaml`.
  static const _workspacesFlag = 1;

  /// `gleon_session_new` flag: take `GLEON_METRICS`, `GLEON_ARTIFACTS_DIR`
  /// and `GLEON_RUN_ID` from the packed strings instead of the process
  /// environment.
  static const _environmentFlag = 2;

  /// Opens a native session: with [hasWorkspaces], each golden belongs to
  /// the nearest directory above it with `.gleon/gleon.yaml`. [environment]
  /// gives the engine's environment variables; when null the native code
  /// reads the process environment.
  ///
  /// Throws a [StateError] when the library is missing or speaks another ABI.
  static Pointer<GleonSessionHandle> openSession({
    required bool hasWorkspaces,
    required GleonEnvironment? environment,
    required GleonIntegration integration,
  }) {
    checkAbiVersion(_abiVersion);
    final GleonIntegration(
      :candidateArtifact,
      :diffArtifact,
      :goldenArtifact,
      :renderer,
      :tool,
      :toolVersion,
    ) = integration;
    final (strings, lengths) = _pack([
      environment?.metrics,
      environment?.artifactsDir,
      environment?.runId,
      tool,
      toolVersion,
      renderer,
      goldenArtifact,
      candidateArtifact,
      diffArtifact,
    ]);

    return GleonFfi.sessionNew(
      (hasWorkspaces ? _workspacesFlag : 0) |
          (environment == null ? 0 : _environmentFlag),
      strings.address,
      strings.length,
      lengths.address,
      lengths.length,
    );
  }

  /// Compares [candidate] with the golden file at [goldenPath] in [session],
  /// or writes it there when [isUpdate]. The candidate is PNG bytes, or the
  /// raw straight RGBA8 pixels of an image of [rawSize] (never for an
  /// update). [tolerance] null uses the golden's `.gleon/gleon.yaml` rule,
  /// else exact; [masks] add to the rule's. [textRegions] (pixels of a raw
  /// candidate) are compared under [textTolerance] (a share of a tile), null
  /// the rule's, else the golden's default (see `matchesGoldenFile`). The
  /// engine may compare or write this platform's own golden beside
  /// [goldenPath] instead (`fallback_platform`). Failure artifacts go to
  /// [failuresDir]; [goldenUri] names the golden in messages.
  ///
  /// The candidate is read in place by the native code; nothing is copied in.
  static NativeOutcome golden(
    GleonSession session, {
    required String goldenPath,
    required String goldenUri,
    required String failuresDir,
    required Uint8List candidate,
    ({int height, int width})? rawSize,
    bool isUpdate = false,
    String? testName,
    GoldenTolerance? tolerance,
    List<PixelRegion> masks = const [],
    List<PixelRegion> textRegions = const [],
    double? textTolerance,
  }) {
    final (strings, lengths) = _pack([
      goldenPath,
      goldenUri,
      failuresDir,
      testName,
    ]);
    final flatMasks = _flat(masks);
    final flatTextRegions = _flat(textRegions);
    final (kind, ratio, similarity, color) = _toleranceArguments(tolerance);
    final call = Struct.create<GleonCall>()
      ..mode = isUpdate ? _updateMode : _compareMode
      ..candidateFormat = rawSize == null ? _pngFormat : _rawFormat
      ..candidateWidth = rawSize?.width ?? 0
      ..candidateHeight = rawSize?.height ?? 0
      ..toleranceKind = kind
      ..maxDiffRatio = ratio
      ..minSimilarity = similarity
      ..colorTolerance = color
      ..textTolerance = textTolerance ?? .nan;
    if (session.isDisposed) {
      throw StateError('gleon: the session was disposed.');
    }
    final summary = Struct.create<GleonSummary>();
    GleonFfi.golden(
      session.handle,
      call.address,
      summary.address,
      strings.address,
      strings.length,
      lengths.address,
      lengths.length,
      candidate.address,
      candidate.length,
      flatMasks.address,
      masks.length,
      flatTextRegions.address,
      textRegions.length,
    );

    return _outcome(summary);
  }

  /// The outcome of [summary], its texts copied out and released. A pass
  /// owns no texts: nothing to copy, nothing to free.
  static NativeOutcome _outcome(GleonSummary summary) {
    final GleonSummary(
      :console,
      :errorKind,
      :message,
      :texts,
      :verdict,
      :warning,
    ) = summary;
    if (texts == nullptr) {
      return NativeOutcome(
        NativeVerdict.of(verdict),
        errorKind: NativeErrorKind.of(errorKind),
      );
    }
    try {
      return NativeOutcome(
        NativeVerdict.of(verdict),
        errorKind: NativeErrorKind.of(errorKind),
        message: _text(message),
        console: _text(console),
        warning: _text(warning),
      );
    } finally {
      GleonFfi.resultFree(texts);
    }
  }

  /// The ABI version reported by [read], the first native call of a process.
  ///
  /// Throws a [StateError] saying what to do when the library is not there:
  /// `dart:ffi` itself only reports an unresolved symbol.
  @visibleForTesting
  static int loadAbiVersion(int Function() read) {
    try {
      return read();
      // ignore: avoid_catching_errors, dart:ffi reports a missing asset so.
    } on ArgumentError catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError(
          'gleon: the native library was not loaded ($error). The build '
          'hook of the gleon package provides it for host `flutter test` on '
          'macOS arm64, Linux x64/arm64 and Windows x64 only: app builds for '
          'devices (Android, iOS) and other targets get none, and web cannot '
          'load it. Run golden tests with `flutter test` on such a host, and '
          'see the package README for the `ffi_path` and `gleon_repo` '
          'user-defines.',
        ),
        stackTrace,
      );
    }
  }

  /// Throws a [StateError] unless [abiVersion] is [expectedAbiVersion].
  @visibleForTesting
  static void checkAbiVersion(int abiVersion) {
    if (abiVersion != expectedAbiVersion) {
      throw StateError(
        'gleon: native library ABI version $abiVersion does not match this '
        'version of the package (ABI $expectedAbiVersion). The library comes '
        'from the `ffi_path` user-define, a `release_url` mirror, a '
        '`gleon_repo` checkout or `native/<target>/` of the package: point '
        'the user-define at the library of this package version, or rebuild '
        'it (`dart bin/build_native.dart`).',
      );
    }
  }

  /// `(kind, maxDiffRatio, minSimilarity, colorTolerance)` of `gleon_golden`:
  /// kind 0 uses the `.gleon/gleon.yaml` rule.
  static (int, double, double, double) _toleranceArguments(
    GoldenTolerance? tolerance,
  ) => switch (tolerance) {
    null => (0, 0, 0, 0),
    ExactTolerance() => (1, 0, 0, 0),
    PixelTolerance(:final maxDiffRatio) => (2, maxDiffRatio, 0, 0),
    SsimTolerance(:final colorTolerance, :final minSimilarity) => (
      3,
      0,
      minSimilarity,
      colorTolerance,
    ),
  };

  /// [regions] as `[x, y, width, height]` quadruples.
  static Uint32List _flat(List<PixelRegion> regions) {
    final flat = Uint32List(regions.length * 4);
    for (final (index, PixelRegion(:height, :width, :x, :y))
        in regions.indexed) {
      flat.setAll(index * 4, [x, y, width, height]);
    }

    return flat;
  }

  /// [strings] packed as `gleon-ffi` expects: their UTF-8 bytes back to back
  /// and each one's byte length; an absent string is empty.
  static (Uint8List, Uint32List) _pack(List<String?> strings) {
    final bytes = BytesBuilder(copy: false);
    final lengths = Uint32List(strings.length);
    for (final (index, text) in strings.indexed) {
      final encoded = text == null ? Uint8List(0) : utf8.encode(text);
      bytes.add(encoded);
      lengths[index] = encoded.length;
    }

    return (bytes.takeBytes(), lengths);
  }

  /// A UTF-8 slice borrowed from the texts of a summary, copied out as a
  /// string. An empty slice has a dangling pointer that is never touched.
  static String _text(NativeSlice slice) => slice.len == 0
      ? _noText
      : utf8.decode(slice.ptr.asTypedList(slice.len), allowMalformed: true);

  static const _noText = '';
}
