import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'native_metrics.dart';
import 'native_timings.dart';

/// Policy version and timings of a comparison that ran.
typedef _Ran = ({int policyVersion, NativeTimings timings});

/// Outcome of one native comparison, parsed from the ABI 4 JSON report
/// (`{abi, policy_version, verdict, baseline?, candidate?, metrics?, regions,
/// timings_us?, error?}`).
@immutable
sealed class NativeReport {
  /// Base constructor of the variants.
  const NativeReport();

  /// Parses a decoded JSON report with patterns (no casts). [diff] is the PNG
  /// diff image the library returned next to it, if any.
  ///
  /// Anything that does not match the contract becomes a [NativeError], never
  /// a pass.
  static NativeReport parse(Object? json, Uint8List? diff) {
    final comparison = _ran(json);

    return switch ((json, comparison)) {
      ({'verdict': 'match', 'metrics': final metrics}, final ran?) =>
        _withMetrics(
          metrics,
          (parsed) => NativeMatch(
            metrics: parsed,
            policyVersion: ran.policyVersion,
            timings: ran.timings,
          ),
        ),
      ({'verdict': 'mismatch'}, final ran?) => _mismatch(json, diff, ran),
      ({'verdict': 'dimension_mismatch'}, final ran?) => _dimensionMismatch(
        json,
        ran,
      ),
      ({'error': final String message, 'verdict': 'error'}, _) => NativeError(
        message,
      ),
      _ => _offContract(json),
    };
  }

  static NativeReport _mismatch(Object? json, Uint8List? diff, _Ran ran) =>
      switch ((json, diff)) {
        (
          {
            'baseline': {'height': final int height, 'width': final int width},
            'metrics': final metrics,
          },
          final diffPng?,
        ) =>
          _withMetrics(
            metrics,
            (parsed) => NativeMismatch(
              width: width,
              height: height,
              metrics: parsed,
              diffPng: diffPng,
              policyVersion: ran.policyVersion,
              timings: ran.timings,
            ),
          ),
        (_, null) => const NativeError('native mismatch without a diff image'),
        _ => _offContract(json),
      };

  static NativeReport _dimensionMismatch(Object? json, _Ran ran) =>
      switch (json) {
        {
          'baseline': {
            'height': final int baselineHeight,
            'width': final int baselineWidth,
          },
          'candidate': {
            'height': final int candidateHeight,
            'width': final int candidateWidth,
          },
        } =>
          NativeDimensionMismatch(
            baselineWidth: baselineWidth,
            baselineHeight: baselineHeight,
            candidateWidth: candidateWidth,
            candidateHeight: candidateHeight,
            policyVersion: ran.policyVersion,
            timings: ran.timings,
          ),
        _ => _offContract(json),
      };

  static _Ran? _ran(Object? json) {
    if (json case {
      'policy_version': final int policyVersion,
      'timings_us': final timingsJson,
    }) {
      final timings = NativeTimings.fromJson(timingsJson);
      if (timings != null) {
        return (policyVersion: policyVersion, timings: timings);
      }
    }

    return null;
  }

  static NativeError _offContract(Object? json) =>
      .new('unexpected native report: ${jsonEncode(json)}');

  static NativeReport _withMetrics(
    Object? json,
    NativeReport Function(NativeMetrics metrics) build,
  ) => switch (NativeMetrics.fromJson(json)) {
    final metrics? => build(metrics),
    null => NativeError('unexpected native metrics: ${jsonEncode(json)}'),
  };
}

/// A comparison that ran: its policy version and native timings.
sealed class NativeComparison extends NativeReport {
  /// Base constructor of the variants.
  const NativeComparison({required this.policyVersion, required this.timings});

  /// Version of the engine's tolerant (SSIM) decision policy.
  final int policyVersion;

  /// Time spent in the native library.
  final NativeTimings timings;
}

/// The images match within the requested tolerance.
final class NativeMatch extends NativeComparison {
  /// Creates a match outcome.
  const NativeMatch({
    required this.metrics,
    required super.policyVersion,
    required super.timings,
  });

  /// What the comparison measured (headroom to the tolerance).
  final NativeMetrics metrics;
}

/// The images differ beyond the requested tolerance.
final class NativeMismatch extends NativeComparison {
  /// Creates a mismatch outcome.
  const NativeMismatch({
    required this.width,
    required this.height,
    required this.metrics,
    required this.diffPng,
    required super.policyVersion,
    required super.timings,
  });

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// What failed and by how much.
  final NativeMetrics metrics;

  /// PNG-encoded diff visualization.
  final Uint8List diffPng;

  /// Short human-readable reason, e.g. `0.02% (1 of 6000px) differ`.
  String get summary => metrics.describe();
}

/// The images have different dimensions.
final class NativeDimensionMismatch extends NativeComparison {
  /// Creates a dimension mismatch outcome.
  const NativeDimensionMismatch({
    required this.baselineWidth,
    required this.baselineHeight,
    required this.candidateWidth,
    required this.candidateHeight,
    required super.policyVersion,
    required super.timings,
  });

  /// Golden (baseline) width.
  final int baselineWidth;

  /// Golden (baseline) height.
  final int baselineHeight;

  /// Candidate (test output) width.
  final int candidateWidth;

  /// Candidate (test output) height.
  final int candidateHeight;

  /// Both sizes, e.g. `golden is 100x60px, test image is 100x61px`.
  String get summary =>
      'golden is ${baselineWidth}x${baselineHeight}px, test image is '
      '${candidateWidth}x${candidateHeight}px';
}

/// Invalid input (e.g. a corrupt PNG) or options; never treated as a pass.
final class NativeError extends NativeReport {
  /// Creates an error outcome.
  const NativeError(this.message);

  /// Human-readable reason.
  final String message;
}
