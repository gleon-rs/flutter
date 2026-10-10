/// Raw `@Native` bindings to the `gleon-ffi` library (`gleon-ffi/src/lib.rs`
/// in the gleon repository). Use `NativeEngine` instead of calling these.
///
/// The asset id is this library's URI and must match `_assetName` in
/// `hook/build.dart`.
///
/// Every call is a leaf call, which is the right trade-off for tests:
///
/// * Inputs are passed zero-copy via `Uint8List.address`,
///   `Uint32List.address` and the `.address` of a `Struct.create`d
///   [GleonCall], which `dart:ffi` only allows for leaf calls, and the
///   native side writes the [GleonSummary] into a `Struct.create`d one, so
///   this side never allocates native memory (no `package:ffi`, no
///   `malloc`/`free` pairs). A summary without texts (a pass) owns nothing:
///   one call per golden. (Not returned by value: leaf calls returning a
///   struct by value with `.address` arguments return null without calling,
///   https://github.com/dart-lang/sdk/issues/64368.)
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

  /// `gleon_golden`: compares or writes one golden given the scalars of
  /// [call], the packed call strings, the candidate (PNG bytes, or raw
  /// straight RGBA8 of the call's width x height) and `[x, y, width, height]`
  /// pixel masks and text regions. Writes the verdict and texts to [summary];
  /// its `texts` (null when there are none) must be released with
  /// [textsFree].
  @Native<
    Void Function(
      Pointer<GleonSessionHandle> session,
      Pointer<GleonCall> call,
      Pointer<GleonSummary> summary,
      Pointer<Uint8> strings,
      Size stringsLength,
      Pointer<Uint32> lengths,
      Size lengthsCount,
      Pointer<Uint8> candidate,
      Size candidateLength,
      Pointer<Uint32> masks,
      Size maskCount,
      Pointer<Uint32> textRegions,
      Size textRegionCount,
    )
  >(symbol: 'gleon_golden', isLeaf: true)
  external static void golden(
    Pointer<GleonSessionHandle> session,
    Pointer<GleonCall> call,
    Pointer<GleonSummary> summary,
    Pointer<Uint8> strings,
    int stringsLength,
    Pointer<Uint32> lengths,
    int lengthsCount,
    Pointer<Uint8> candidate,
    int candidateLength,
    Pointer<Uint32> masks,
    int maskCount,
    Pointer<Uint32> textRegions,
    int textRegionCount,
  );

  /// `gleon_texts_free`: releases the texts of a summary (and every slice
  /// borrowed from them), once.
  @Native<Void Function(Pointer<GleonTexts> texts)>(
    symbol: 'gleon_texts_free',
    isLeaf: true,
  )
  external static void textsFree(Pointer<GleonTexts> texts);
}

/// Opaque texts of a `GleonSummary` owned by the native library: created by
/// `gleon_golden`, released only by `gleon_texts_free`.
final class GleonTexts extends Opaque {}

/// Opaque `GleonSession` owned by the native library: created by
/// `gleon_session_new`, released only by `gleon_session_free`.
final class GleonSessionHandle extends Opaque {}

/// The safer-ffi `c_slice::Ref<u8>` fields of a `GleonSummary`: a borrowed
/// view into its texts, valid until they are freed (empty for "none").
final class NativeSlice extends Struct {
  /// First byte (dangling when [len] is 0).
  external Pointer<Uint8> ptr;

  /// Number of bytes.
  @Size()
  external int len;
}

/// The `GleonCall` scalars of one `gleon_golden` call, created on the Dart
/// heap and passed by `.address` (the native side reads them unaligned).
final class GleonCall extends Struct {
  /// Pixel tolerance: the largest share of differing pixels.
  @Double()
  external double maxDiffRatio;

  /// SSIM tolerance: the lowest local similarity.
  @Double()
  external double minSimilarity;

  /// SSIM tolerance: the color deviation beyond the envelope.
  @Double()
  external double colorTolerance;

  /// The tolerance of text, a share of a tile; NaN for the rule's.
  @Double()
  external double textTolerance;

  /// Width of a raw candidate.
  @Uint32()
  external int candidateWidth;

  /// Height of a raw candidate.
  @Uint32()
  external int candidateHeight;

  /// 0 compare, 1 update (PNG only).
  @Uint8()
  external int mode;

  /// 0 PNG bytes, 1 raw straight RGBA8 pixels.
  @Uint8()
  external int candidateFormat;

  /// 0 the `.gleon/gleon.yaml` rule, 1 exact, 2 pixel, 3 SSIM.
  @Uint8()
  external int toleranceKind;

  /// Pixel tolerance: the largest RGBA byte delta a pixel may differ by and
  /// still count as equal (0: off).
  @Uint8()
  external int channelTolerance;

  /// Pixel tolerance: 1 lets anti-aliased pixels pass, 0 not.
  @Uint8()
  external int antiAlias;

  /// Pixel tolerance: differing pixels on the golden's edges (Sobel gradient
  /// above this) pass, outside text (0: off).
  @Uint8()
  external int edgeThreshold;
}

/// The `GleonSummary` `gleon_golden` writes: the verdict code and the UTF-8
/// texts to show, owned by [texts].
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

  /// Owns the texts until `gleon_texts_free`; null when all are empty.
  external Pointer<GleonTexts> texts;
}
