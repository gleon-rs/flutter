/// Raw `@Native` bindings to the `gleon-ffi` library (`gleon-ffi/src/lib.rs`
/// in the gleon repository). Use `NativeEngine` instead of calling these.
///
/// The asset id is this library's URI and must match `_assetName` in
/// `hook/build.dart`.
///
/// Every call is a leaf call, which is the right trade-off for tests:
///
/// * Inputs are passed zero-copy via `Uint8List.address` and
///   `Uint32List.address`, which `dart:ffi` only allows for leaf calls, and
///   the result summary is returned by value, so this side never allocates
///   native memory (no `package:ffi`, no `malloc`/`free` pairs).
/// * The price: while a leaf call runs, the isolate group cannot reach a GC
///   safepoint. Typical goldens take milliseconds (the native side also
///   writes failure artifacts and case reports); large SSIM comparisons can
///   take seconds. The calling test awaits the result anyway, so nothing
///   useful is blocked, and `flutter test` parallelizes across processes.
@DefaultAsset('package:gleon/src/core/native/gleon_ffi.dart')
library;

// The bindings and the C types they exchange mirror one contract.
// ignore_for_file: prefer-single-declaration-per-file

import 'dart:ffi';

/// `gleon-ffi` C ABI (safer-ffi). The strings of a call are packed into one
/// UTF-8 buffer plus a `Uint32List` of their byte lengths (see
/// `NativeEngine`); an empty string stands for an absent optional one.
abstract final class GleonFfi {
  /// `gleon_ffi_abi_version`: the C contract version of the library.
  @Native<Uint32 Function()>(symbol: 'gleon_ffi_abi_version', isLeaf: true)
  external static int abiVersion();

  /// `gleon_session_new`: the per-process state (workspace, config, names of
  /// this integration) from `flags` and the packed session strings. Never
  /// returns null; release with [sessionFree].
  @Native<
    Pointer<GleonSessionHandle> Function(
      Uint32 flags,
      Pointer<Uint8> strings,
      Size stringsLength,
      Pointer<Uint32> lengths,
      Size lengthsCount,
    )
  >(symbol: 'gleon_session_new', isLeaf: true)
  external static Pointer<GleonSessionHandle> sessionNew(
    int flags,
    Pointer<Uint8> strings,
    int stringsLength,
    Pointer<Uint32> lengths,
    int lengthsCount,
  );

  /// `gleon_session_free`: releases a session.
  @Native<Void Function(Pointer<GleonSessionHandle> session)>(
    symbol: 'gleon_session_free',
    isLeaf: true,
  )
  external static void sessionFree(Pointer<GleonSessionHandle> session);

  /// `gleon_golden`: compares (mode 0) or writes (mode 1) one golden given
  /// the packed call strings, with the tolerance code (0 from
  /// `.gleon/gleon.yaml`, 1 exact, 2 pixel, 3 SSIM) and `[x, y, width,
  /// height]` pixel masks. Never returns null; release with [resultFree].
  @Native<
    Pointer<GleonResult> Function(
      Pointer<GleonSessionHandle> session,
      Uint8 mode,
      Pointer<Uint8> strings,
      Size stringsLength,
      Pointer<Uint32> lengths,
      Size lengthsCount,
      Pointer<Uint8> candidate,
      Size candidateLength,
      Uint8 toleranceKind,
      Double maxDiffRatio,
      Double minSimilarity,
      Double colorTolerance,
      Pointer<Uint32> masks,
      Size maskCount,
    )
  >(symbol: 'gleon_golden', isLeaf: true)
  external static Pointer<GleonResult> golden(
    Pointer<GleonSessionHandle> session,
    int mode,
    Pointer<Uint8> strings,
    int stringsLength,
    Pointer<Uint32> lengths,
    int lengthsCount,
    Pointer<Uint8> candidate,
    int candidateLength,
    int toleranceKind,
    double maxDiffRatio,
    double minSimilarity,
    double colorTolerance,
    Pointer<Uint32> masks,
    int maskCount,
  );

  /// `gleon_result_summary`: the verdict and texts, borrowed from [result].
  @Native<GleonSummary Function(Pointer<GleonResult> result)>(
    symbol: 'gleon_result_summary',
    isLeaf: true,
  )
  external static GleonSummary resultSummary(Pointer<GleonResult> result);

  /// `gleon_result_free`: releases [result] and every slice borrowed from it.
  @Native<Void Function(Pointer<GleonResult> result)>(
    symbol: 'gleon_result_free',
    isLeaf: true,
  )
  external static void resultFree(Pointer<GleonResult> result);
}

/// Opaque `GleonResult` owned by the native library: created by
/// `gleon_golden`, released only by `gleon_result_free`.
final class GleonResult extends Opaque {}

/// Opaque `GleonSession` owned by the native library: created by
/// `gleon_session_new`, released only by `gleon_session_free`.
final class GleonSessionHandle extends Opaque {}

/// The safer-ffi `c_slice::Ref<u8>` returned by value: a borrowed view into a
/// `GleonResult`, valid until the result is freed (empty for "none").
final class NativeSlice extends Struct {
  /// First byte (dangling when [len] is 0).
  external Pointer<Uint8> ptr;

  /// Number of bytes.
  @Size()
  external int len;
}

/// The `GleonSummary` returned by value from `gleon_result_summary`: the
/// verdict code and the UTF-8 texts to show, borrowed from their result.
final class GleonSummary extends Struct {
  /// Verdict code, see `NativeVerdict`.
  @Uint8()
  external int verdict;

  /// Error kind code, see `NativeErrorKind`.
  @Uint8()
  external int errorKind;

  /// The test failure message; empty for a pass.
  external NativeSlice message;

  /// The console line to print; usually empty.
  external NativeSlice console;

  /// Warnings to print, one per line; usually empty.
  external NativeSlice warning;
}
