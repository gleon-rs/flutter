import 'package:meta/meta.dart';

import '../compare/pixel_region.dart';

/// Whole-image comparison metrics (the `Metrics` of `gleon-model`), reported
/// for matches and mismatches alike.
@immutable
sealed class NativeMetrics {
  /// Base constructor of the variants.
  const NativeMetrics();

  /// Parses the internally tagged JSON (`{"kind": "pixel", ...}`) with
  /// patterns, or returns null for another shape.
  static NativeMetrics? fromJson(Object? json) => switch (json) {
    {
      'diff_pixels': final int diffPixels,
      'diff_ratio': final num diffRatio,
      'headroom': final num headroom,
      'kind': 'pixel',
      'total_pixels': final int totalPixels,
    } =>
      PixelMetrics(
        totalPixels: totalPixels,
        diffPixels: diffPixels,
        diffRatio: diffRatio.toDouble(),
        headroom: headroom.toDouble(),
      ),
    {
      'changed_pixels': final int changedPixels,
      'failing_pixels': final int failingPixels,
      'headroom': {
        'color': final num colorHeadroom,
        'similarity': final num similarityHeadroom,
      },
      'kind': 'ssim',
      'mean_ssim': final num meanSsim,
      'min_ssim': final num minSsim,
      'peak_excess': final num peakExcess,
    } =>
      SsimMetrics(
        minSsim: minSsim.toDouble(),
        meanSsim: meanSsim.toDouble(),
        peakExcess: peakExcess.toDouble(),
        changedPixels: changedPixels,
        failingPixels: failingPixels,
        similarityHeadroom: similarityHeadroom.toDouble(),
        colorHeadroom: colorHeadroom.toDouble(),
        changedRegion: PixelRegion.fromNativeJson(json['changed_region']),
        failingRegion: PixelRegion.fromNativeJson(json['failing_region']),
      ),
    _ => null,
  };

  /// Short human-readable failure reason.
  String describe();

  /// The `Metrics` JSON of `gleon-model` (for case reports).
  Map<String, Object> toJson();
}

/// Exact and pixel tolerances: how many pixels differ.
final class PixelMetrics extends NativeMetrics {
  /// Creates the metrics.
  const PixelMetrics({
    required this.totalPixels,
    required this.diffPixels,
    required this.diffRatio,
    required this.headroom,
  });

  /// Pixels compared.
  final int totalPixels;

  /// Pixels whose RGBA bytes differ.
  final int diffPixels;

  /// `diffPixels / totalPixels`.
  final double diffRatio;

  /// `maxDiffRatio - diffRatio`; negative means it failed.
  final double headroom;

  @override
  int get hashCode => Object.hash(totalPixels, diffPixels, diffRatio, headroom);

  @override
  String describe() {
    final percent = (diffRatio * 100).toStringAsFixed(2);

    return '$percent% ($diffPixels of ${totalPixels}px) differ';
  }

  @override
  Map<String, Object> toJson() => {
    'diff_pixels': diffPixels,
    'diff_ratio': diffRatio,
    'headroom': headroom,
    'kind': 'pixel',
    'total_pixels': totalPixels,
  };

  @override
  bool operator ==(Object other) =>
      other is PixelMetrics &&
      other.totalPixels == totalPixels &&
      other.diffPixels == diffPixels &&
      other.diffRatio == diffRatio &&
      other.headroom == headroom;
}

/// SSIM tolerance: the gate values and their headroom.
final class SsimMetrics extends NativeMetrics {
  /// Creates the metrics.
  const SsimMetrics({
    required this.minSsim,
    required this.meanSsim,
    required this.peakExcess,
    required this.changedPixels,
    required this.failingPixels,
    required this.similarityHeadroom,
    required this.colorHeadroom,
    this.changedRegion,
    this.failingRegion,
  });

  /// Lowest local SSIM (gated by `minSimilarity`).
  final double minSsim;

  /// Mean local SSIM; diagnostic only.
  final double meanSsim;

  /// Largest deviation beyond the local envelope over the changed pixels, in
  /// 8-bit channel units, with `colorTolerance` not subtracted.
  final double peakExcess;

  /// Pixels whose RGBA bytes differ.
  final int changedPixels;

  /// Bounding box of the changed pixels.
  final PixelRegion? changedRegion;

  /// Pixels failing the policy.
  final int failingPixels;

  /// Bounding box of the changed pixels that failed the policy.
  final PixelRegion? failingRegion;

  /// `minSsim - minSimilarity`.
  final double similarityHeadroom;

  /// `colorTolerance - peakExcess`.
  final double colorHeadroom;

  @override
  int get hashCode => Object.hash(
    minSsim,
    meanSsim,
    peakExcess,
    changedPixels,
    changedRegion,
    failingPixels,
    failingRegion,
    similarityHeadroom,
    colorHeadroom,
  );

  @override
  String describe() {
    final peak = peakExcess.toStringAsFixed(1);
    final gates = [
      'min local SSIM ${minSsim.toStringAsFixed(4)}',
      if (colorHeadroom < 0) 'colors deviate by up to $peak (8-bit units)',
    ].join(', ');

    return switch (failingRegion) {
      final bounds? => 'changed area at $bounds: $gates',
      null => gates,
    };
  }

  @override
  Map<String, Object> toJson() => {
    'changed_pixels': changedPixels,
    'changed_region': ?changedRegion?.toNativeJson(),
    'failing_pixels': failingPixels,
    'failing_region': ?failingRegion?.toNativeJson(),
    'headroom': {'color': colorHeadroom, 'similarity': similarityHeadroom},
    'kind': 'ssim',
    'mean_ssim': meanSsim,
    'min_ssim': minSsim,
    'peak_excess': peakExcess,
  };

  @override
  bool operator ==(Object other) =>
      other is SsimMetrics &&
      other.minSsim == minSsim &&
      other.meanSsim == meanSsim &&
      other.peakExcess == peakExcess &&
      other.changedPixels == changedPixels &&
      other.changedRegion == changedRegion &&
      other.failingPixels == failingPixels &&
      other.failingRegion == failingRegion &&
      other.similarityHeadroom == similarityHeadroom &&
      other.colorHeadroom == colorHeadroom;
}
