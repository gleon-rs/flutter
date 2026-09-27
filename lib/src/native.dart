// Dart FFI bindings to the `gleon-ffi` native library (see `gleon-ffi/src/lib.rs`).
//
// The asset id must match `_assetName` in `hook/build.dart`.
//
// Every call is a leaf call: input bytes are passed zero-copy via
// `Uint8List.address` (only allowed for leaf calls), and the result getters
// return `{ptr, len}` slices by value, so no native allocations are needed on
// this side. A leaf call keeps the isolate group from reaching a GC safepoint
// until it returns. Typical goldens take milliseconds, but the engine runs
// single-threaded here and large SSIM comparisons can take seconds; that is
// acceptable because the calling test awaits the result anyway.
@DefaultAsset('package:gleon/src/native.dart')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

/// JSON contract version this Dart code understands (`ABI_VERSION` in `gleon-ffi`).
const int expectedAbiVersion = 3;

final class _GleonResult extends Opaque {}

/// safer-ffi `c_slice::Ref<u8>` (`ptr` is null for "none").
final class _Slice extends Struct {
  external Pointer<Uint8> ptr;

  @Size()
  external int len;
}

@Native<Uint32 Function()>(symbol: 'gleon_ffi_abi_version', isLeaf: true)
external int _abiVersion();

@Native<
  Pointer<_GleonResult> Function(
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'gleon_compare', isLeaf: true)
external Pointer<_GleonResult> _compare(
  Pointer<Uint8> baseline,
  int baselineLength,
  Pointer<Uint8> candidate,
  int candidateLength,
  Pointer<Uint8> options,
  int optionsLength,
);

@Native<_Slice Function(Pointer<_GleonResult>)>(
  symbol: 'gleon_result_json',
  isLeaf: true,
)
external _Slice _resultJson(Pointer<_GleonResult> result);

@Native<_Slice Function(Pointer<_GleonResult>)>(
  symbol: 'gleon_result_diff_png',
  isLeaf: true,
)
external _Slice _resultDiffPng(Pointer<_GleonResult> result);

@Native<Void Function(Pointer<_GleonResult>)>(
  symbol: 'gleon_result_free',
  isLeaf: true,
)
external void _resultFree(Pointer<_GleonResult> result);

/// Outcome of a native comparison.
sealed class NativeComparison {
  /// Base constructor.
  const NativeComparison();
}

/// The images match within the requested tolerance.
final class NativeMatch extends NativeComparison {
  /// Creates a match outcome.
  const NativeMatch();
}

/// The images differ beyond the requested tolerance.
final class NativeMismatch extends NativeComparison {
  /// Creates a mismatch outcome.
  const NativeMismatch({
    required this.width,
    required this.height,
    required this.diffPng,
    this.diffPixels,
    this.minSsim,
    this.maxExcess,
    this.region,
  });

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Number of differing pixels (pixel/exact mode).
  final int? diffPixels;

  /// Lowest local SSIM (SSIM mode).
  final double? minSsim;

  /// Largest deviation beyond the local envelope, 8-bit units (SSIM mode).
  final double? maxExcess;

  /// Bounding box of the failing change as `(x, y, width, height)` (SSIM mode).
  final ({int x, int y, int width, int height})? region;

  /// PNG-encoded diff visualization.
  final Uint8List diffPng;

  /// Total number of pixels compared.
  int get totalPixels => width * height;
}

/// The images have different dimensions.
final class NativeDimensionMismatch extends NativeComparison {
  /// Creates a dimension mismatch outcome.
  const NativeDimensionMismatch({
    required this.baselineWidth,
    required this.baselineHeight,
    required this.candidateWidth,
    required this.candidateHeight,
  });

  /// Golden (baseline) width.
  final int baselineWidth;

  /// Golden (baseline) height.
  final int baselineHeight;

  /// Candidate (test output) width.
  final int candidateWidth;

  /// Candidate (test output) height.
  final int candidateHeight;
}

/// Invalid input (e.g. a corrupt PNG) or options; never treated as a pass.
final class NativeError extends NativeComparison {
  /// Creates an error outcome.
  const NativeError(this.message);

  /// Human-readable reason.
  final String message;
}

bool _abiChecked = false;

void _ensureAbi() {
  if (_abiChecked) return;
  final actual = _abiVersion();
  if (actual != expectedAbiVersion) {
    throw StateError(
      'gleon: native library ABI version $actual does not match the Dart '
      'package ($expectedAbiVersion). Rebuild the native library.',
    );
  }
  _abiChecked = true;
}

/// Compares PNG-encoded [baseline] and [candidate] with JSON-serializable [options]
/// (`{mode, threshold?, min_similarity?, color_tolerance?, masks?}`).
///
/// The buffers are read in place by the native code; nothing is copied in.
NativeComparison compareNative({
  required Uint8List baseline,
  required Uint8List candidate,
  required Map<String, Object?> options,
}) {
  _ensureAbi();
  final optionsBytes = utf8.encode(jsonEncode(options));
  final result = _compare(
    baseline.address,
    baseline.length,
    candidate.address,
    candidate.length,
    optionsBytes.address,
    optionsBytes.length,
  );
  try {
    final json = _resultJson(result);
    if (json.ptr == nullptr) {
      return const NativeError('native result without a report');
    }
    final report = jsonDecode(
      utf8.decode(json.ptr.asTypedList(json.len)),
    ) as Map<String, Object?>;
    final diff = _resultDiffPng(result);
    final diffPng = diff.ptr == nullptr
        ? null
        : Uint8List.fromList(diff.ptr.asTypedList(diff.len));
    return _parse(report, diffPng);
  } finally {
    _resultFree(result);
  }
}

NativeComparison _parse(Map<String, Object?> report, Uint8List? diffPng) {
  List<int> size(String key) => (report[key]! as List<Object?>)
      .cast<num>()
      .map((n) => n.toInt())
      .toList();

  switch (report['verdict']) {
    case 'match':
      return const NativeMatch();
    case 'dimension_mismatch':
      final baseline = size('baseline_size');
      final candidate = size('candidate_size');
      return NativeDimensionMismatch(
        baselineWidth: baseline[0],
        baselineHeight: baseline[1],
        candidateWidth: candidate[0],
        candidateHeight: candidate[1],
      );
    case 'mismatch':
      final baseline = size('baseline_size');
      final detail = report['detail']! as Map<String, Object?>;
      final pixel = detail['Pixel'] as Map<String, Object?>?;
      final ssim = detail['Ssim'] as Map<String, Object?>?;
      if (diffPng == null) {
        return const NativeError('native mismatch without a diff image');
      }
      final region = ssim?['region'] as Map<String, Object?>?;
      int field(String key) => (region![key]! as num).toInt();
      return NativeMismatch(
        width: baseline[0],
        height: baseline[1],
        diffPng: diffPng,
        diffPixels: (pixel?['diff_count'] as num?)?.toInt(),
        minSsim: (ssim?['min_ssim'] as num?)?.toDouble(),
        maxExcess: (ssim?['max_excess'] as num?)?.toDouble(),
        region: region == null
            ? null
            : (
                x: field('x'),
                y: field('y'),
                width: field('width'),
                height: field('height'),
              ),
      );
    case 'error':
      return NativeError(report['error'] as String? ?? 'unknown native error');
    default:
      return NativeError('unexpected native verdict: ${report['verdict']}');
  }
}
