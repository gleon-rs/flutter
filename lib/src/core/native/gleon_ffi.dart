/// Raw `@Native` bindings to the `gleon-ffi` library (`gleon-ffi/src/lib.rs`
/// in the gleon repository). Use `NativeEngine` instead of calling these.
///
/// The asset id is this library's URI and must match `_assetName` in
/// `hook/build.dart`.
///
/// Every call is a leaf call, which is the right trade-off for tests:
///
/// * Inputs are passed zero-copy via `Uint8List.address`, which `dart:ffi`
///   only allows for leaf calls, and result getters return `{ptr, len}` slices
///   by value, so this side never allocates native memory (no `package:ffi`,
///   no `malloc`/`free` pairs, no finalizers).
/// * The price: while a leaf call runs, the isolate group cannot reach a GC
///   safepoint. Typical goldens take milliseconds; large SSIM comparisons can
///   take seconds. The calling test awaits the result anyway, so nothing
///   useful is blocked, and `flutter test` parallelizes across processes.
/// * The alternative (frigate's approach: copy inputs into `malloc`ed memory
///   and run a non-leaf call in `Isolate.run`) keeps the isolate responsive,
///   which apps need but tests do not, at the cost of copies and manual
///   lifetime management.
@DefaultAsset('package:gleon/src/core/native/gleon_ffi.dart')
library;

import 'dart:ffi';

import 'gleon_result.dart';
import 'native_slice.dart';

/// `gleon-ffi` C ABI (safer-ffi, JSON over byte slices).
abstract final class GleonFfi {
  /// `gleon_ffi_abi_version`: the JSON contract version of the library.
  @Native<Uint32 Function()>(symbol: 'gleon_ffi_abi_version', isLeaf: true)
  external static int abiVersion();

  /// `gleon_compare`: compares two PNG buffers with JSON options. Never
  /// returns null; the result must be released with [resultFree].
  @Native<
    Pointer<GleonResult> Function(
      Pointer<Uint8> baseline,
      Size baselineLength,
      Pointer<Uint8> candidate,
      Size candidateLength,
      Pointer<Uint8> options,
      Size optionsLength,
    )
  >(symbol: 'gleon_compare', isLeaf: true)
  external static Pointer<GleonResult> compare(
    Pointer<Uint8> baseline,
    int baselineLength,
    Pointer<Uint8> candidate,
    int candidateLength,
    Pointer<Uint8> options,
    int optionsLength,
  );

  /// `gleon_config_resolve`: validates `.gleon/gleon.yaml` text and resolves
  /// the rule of one golden path (`metricsEnv` null when `GLEON_METRICS` is
  /// unset). Never returns null; release with [resultFree].
  @Native<
    Pointer<GleonResult> Function(
      Pointer<Uint8> yaml,
      Size yamlLength,
      Pointer<Uint8> path,
      Size pathLength,
      Pointer<Uint8> metricsEnv,
      Size metricsEnvLength,
    )
  >(symbol: 'gleon_config_resolve', isLeaf: true)
  external static Pointer<GleonResult> configResolve(
    Pointer<Uint8> yaml,
    int yamlLength,
    Pointer<Uint8> path,
    int pathLength,
    Pointer<Uint8> metricsEnv,
    int metricsEnvLength,
  );

  /// `gleon_result_json`: the UTF-8 JSON report, borrowed from [result].
  @Native<NativeSlice Function(Pointer<GleonResult> result)>(
    symbol: 'gleon_result_json',
    isLeaf: true,
  )
  external static NativeSlice resultJson(Pointer<GleonResult> result);

  /// `gleon_result_diff_png`: the PNG diff image (mismatches only), borrowed
  /// from [result].
  @Native<NativeSlice Function(Pointer<GleonResult> result)>(
    symbol: 'gleon_result_diff_png',
    isLeaf: true,
  )
  external static NativeSlice resultDiffPng(Pointer<GleonResult> result);

  /// `gleon_result_free`: releases [result] and every slice borrowed from it.
  @Native<Void Function(Pointer<GleonResult> result)>(
    symbol: 'gleon_result_free',
    isLeaf: true,
  )
  external static void resultFree(Pointer<GleonResult> result);
}
