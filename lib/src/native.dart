// Dart FFI bindings to the `gleon-ffi` native library (see `gleon-ffi/src/lib.rs`).
//
// The asset id must match `_assetName` in `hook/build.dart`.
@DefaultAsset('package:gleon/src/native.dart')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// JSON contract version this Dart code understands (`ABI_VERSION` in `gleon-ffi`).
const int expectedAbiVersion = 2;

final class _GleonResult extends Opaque {}

@Native<Uint32 Function()>(symbol: 'gleon_ffi_abi_version')
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
>(symbol: 'gleon_compare')
external Pointer<_GleonResult> _compare(
  Pointer<Uint8> baseline,
  int baselineLength,
  Pointer<Uint8> candidate,
  int candidateLength,
  Pointer<Uint8> options,
  int optionsLength,
);

@Native<Pointer<Uint8> Function(Pointer<_GleonResult>, Pointer<Size>)>(
  symbol: 'gleon_result_json',
)
external Pointer<Uint8> _resultJson(
  Pointer<_GleonResult> result,
  Pointer<Size> length,
);

@Native<Pointer<Uint8> Function(Pointer<_GleonResult>, Pointer<Size>)>(
  symbol: 'gleon_result_diff_png',
)
external Pointer<Uint8> _resultDiffPng(
  Pointer<_GleonResult> result,
  Pointer<Size> length,
);

@Native<Void Function(Pointer<_GleonResult>)>(symbol: 'gleon_result_free')
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
/// (`{mode, threshold?, min_similarity?, masks?}`).
///
/// Buffers are copied into native memory for the duration of the call and freed afterwards.
NativeComparison compareNative({
  required List<int> baseline,
  required List<int> candidate,
  required Map<String, Object?> options,
}) {
  _ensureAbi();
  final optionsBytes = utf8.encode(jsonEncode(options));
  return using((arena) {
    Pointer<Uint8> copy(List<int> bytes) {
      final ptr = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return ptr;
    }

    final result = _compare(
      copy(baseline),
      baseline.length,
      copy(candidate),
      candidate.length,
      copy(optionsBytes),
      optionsBytes.length,
    );
    try {
      final length = arena<Size>();
      final jsonPtr = _resultJson(result, length);
      final report =
          jsonDecode(utf8.decode(jsonPtr.asTypedList(length.value)))
              as Map<String, Object?>;
      final diffPtr = _resultDiffPng(result, length);
      final diffPng = diffPtr == nullptr
          ? null
          : Uint8List.fromList(diffPtr.asTypedList(length.value));
      return _parse(report, diffPng);
    } finally {
      _resultFree(result);
    }
  });
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
