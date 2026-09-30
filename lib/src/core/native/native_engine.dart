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
  static const expectedAbiVersion = 6;

  /// Releases sessions that are garbage collected.
  static final sessionFinalizer = NativeFinalizer(
    Native.addressOf<
          NativeFunction<Void Function(Pointer<GleonSessionHandle> session)>
        >(GleonFfi.sessionFree)
        .cast<NativeFinalizerFunction>(),
  );

  /// Asked once per process, on the first call.
  // ignore: avoid-explicit-type-declaration, not obvious from the initializer.
  static final int _abiVersion = loadAbiVersion(GleonFfi.abiVersion);

  /// `gleon_session_new` flag: each golden belongs to the nearest directory
  /// above it with `.gleon/gleon.yaml`.
  static const _workspacesFlag = 1;

  /// `gleon_session_new` flag: use the given `GLEON_METRICS` value instead of
  /// the process environment.
  static const _metricsEnvFlag = 2;

  /// Opens a native session: with [hasWorkspaces], each golden belongs to
  /// the nearest directory above it with `.gleon/gleon.yaml`. [metricsEnv]
  /// overrides `GLEON_METRICS` (empty for unset); when null the native code
  /// reads the environment.
  ///
  /// Throws a [StateError] when the library is missing or speaks another ABI.
  static Pointer<GleonSessionHandle> openSession({
    required bool hasWorkspaces,
    required String? metricsEnv,
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
      metricsEnv,
      tool,
      toolVersion,
      renderer,
      goldenArtifact,
      candidateArtifact,
      diffArtifact,
    ]);

    return GleonFfi.sessionNew(
      (hasWorkspaces ? _workspacesFlag : 0) |
          (metricsEnv == null ? 0 : _metricsEnvFlag),
      strings.address,
      strings.length,
      lengths.address,
      lengths.length,
    );
  }

  /// Compares the PNG [candidate] with the golden file at [goldenPath] in
  /// [session], or writes it there when [isUpdate]. [tolerance] null uses the
  /// golden's `.gleon/gleon.yaml` rule, else exact; [masks] add to the
  /// rule's. Failure artifacts go to [failuresDir]; [goldenUri] names the
  /// golden in messages.
  ///
  /// The candidate is read in place by the native code; nothing is copied in.
  static NativeOutcome golden(
    GleonSession session, {
    required String goldenPath,
    required String goldenUri,
    required String failuresDir,
    required Uint8List candidate,
    bool isUpdate = false,
    String? testName,
    GoldenTolerance? tolerance,
    List<PixelRegion> masks = const [],
  }) {
    final (strings, lengths) = _pack([
      goldenPath,
      goldenUri,
      failuresDir,
      testName,
    ]);
    final flatMasks = _flat(masks);
    final (kind, ratio, similarity, color) = _toleranceArguments(tolerance);
    final result = GleonFfi.golden(
      session.handle,
      isUpdate ? 1 : 0,
      strings.address,
      strings.length,
      lengths.address,
      lengths.length,
      candidate.address,
      candidate.length,
      kind,
      ratio,
      similarity,
      color,
      flatMasks.address,
      masks.length,
    );
    try {
      final GleonSummary(:console, :errorKind, :message, :verdict, :warning) =
          GleonFfi.resultSummary(result);

      return NativeOutcome(
        NativeVerdict.of(verdict),
        errorKind: NativeErrorKind.of(errorKind),
        message: _text(message),
        console: _text(console),
        warning: _text(warning),
      );
    } finally {
      GleonFfi.resultFree(result);
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
          'gleon: the native library was not loaded ($error). It is provided '
          'by the build hook of the gleon package for `flutter test` on macOS '
          'arm64, Linux and Windows x64 (not web or devices); run the tests '
          'with `flutter test` and see the package README for the `ffi_path` '
          'and `gleon_repo` user-defines.',
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
        'gleon: native library ABI version $abiVersion does not match the '
        'Dart package ($expectedAbiVersion). Rebuild the native library.',
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

  /// [masks] as `[x, y, width, height]` quadruples.
  static Uint32List _flat(List<PixelRegion> masks) {
    final flat = Uint32List(masks.length * 4);
    for (final (index, PixelRegion(:height, :width, :x, :y)) in masks.indexed) {
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

  /// A UTF-8 slice borrowed from a result, copied out as a string. An empty
  /// slice (the common case: a pass has no texts) has a dangling pointer that
  /// is never touched.
  static String _text(NativeSlice slice) => slice.len == 0
      ? _noText
      : utf8.decode(slice.ptr.asTypedList(slice.len), allowMalformed: true);

  static const _noText = '';
}
