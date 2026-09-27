import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// How a golden image is compared against its baseline.
enum GoldenMode {
  /// Every pixel must be identical. Same behavior as Flutter's default
  /// `matchesGoldenFile`, and the default of this package.
  exact,

  /// Passes when the fraction of differing pixels is at most `threshold`.
  pixel,

  /// Tolerates rendering noise (anti-aliasing, sub-pixel geometry, glyph
  /// weight, imperceptible color drift) while catching changed, added or
  /// removed content, color and alpha changes and blur.
  ///
  /// Two gates must pass: every local neighborhood keeps an SSIM of at least
  /// `minSimilarity` (at half resolution), and no patch of pixels deviates
  /// from its local 3x3 envelope by more than `colorTolerance`.
  ///
  /// Known limits: glyphs moved by half a pixel or more (typical of different
  /// operating systems' font engines) fail, so keep per-platform goldens;
  /// low-contrast color changes of one-pixel lines can pass.
  ssim,
}

/// Default comparison settings used by `matchesGoldenFile` when a parameter is
/// not passed explicitly. Assign [gleonGoldenDefaults] (for example in
/// `flutter_test_config.dart`) to change them for a whole test suite.
@immutable
final class GleonGoldenConfig {
  /// Creates a configuration. Defaults keep Flutter's exact comparison.
  const GleonGoldenConfig({
    this.mode = GoldenMode.exact,
    this.threshold = 0.01,
    this.minSimilarity = 0.8,
    this.colorTolerance = 8,
    this.ignoreRegions = const <Rect>[],
  });

  /// Comparison mode.
  final GoldenMode mode;

  /// Maximum fraction (0.0–1.0) of differing pixels for [GoldenMode.pixel].
  final double threshold;

  /// Minimum local SSIM (0.0–1.0) for [GoldenMode.ssim].
  final double minSimilarity;

  /// Tolerated deviation beyond the local envelope, in 8-bit channel units
  /// (0–255), for [GoldenMode.ssim].
  final double colorTolerance;

  /// Regions excluded from the comparison, in pixels of the golden PNG
  /// (origin top-left). Measure them on the golden file itself: its scale
  /// depends on what was captured (e.g. a whole `MaterialApp` is captured at
  /// the test view's physical size, 2400x1800 by default).
  final List<Rect> ignoreRegions;

  /// Returns a copy with the given fields replaced.
  GleonGoldenConfig copyWith({
    GoldenMode? mode,
    double? threshold,
    double? minSimilarity,
    double? colorTolerance,
    List<Rect>? ignoreRegions,
  }) => GleonGoldenConfig(
    mode: mode ?? this.mode,
    threshold: threshold ?? this.threshold,
    minSimilarity: minSimilarity ?? this.minSimilarity,
    colorTolerance: colorTolerance ?? this.colorTolerance,
    ignoreRegions: ignoreRegions ?? this.ignoreRegions,
  );
}

/// Suite-wide defaults for `matchesGoldenFile`.
///
/// ```dart
/// // test/flutter_test_config.dart
/// Future<void> testExecutable(FutureOr<void> Function() testMain) async {
///   gleonGoldenDefaults = const GleonGoldenConfig(mode: GoldenMode.ssim);
///   await testMain();
/// }
/// ```
GleonGoldenConfig gleonGoldenDefaults = const GleonGoldenConfig();

/// Fully resolved and validated options for one comparison.
@immutable
final class ResolvedGoldenOptions {
  const ResolvedGoldenOptions._({
    required this.mode,
    required this.threshold,
    required this.minSimilarity,
    required this.colorTolerance,
    required this.ignoreRegions,
  });

  /// Merges explicit per-call arguments over [defaults] and validates them.
  ///
  /// Throws [ArgumentError] for out-of-range values or for a per-call
  /// parameter that does not apply to the resolved mode.
  factory ResolvedGoldenOptions.resolve({
    required GleonGoldenConfig defaults,
    GoldenMode? mode,
    double? threshold,
    double? minSimilarity,
    double? colorTolerance,
    List<Rect>? ignoreRegions,
  }) {
    final resolvedMode = mode ?? defaults.mode;
    if (threshold != null && resolvedMode != GoldenMode.pixel) {
      throw ArgumentError.value(
        threshold,
        'threshold',
        'only applies to GoldenMode.pixel (mode is ${resolvedMode.name})',
      );
    }
    if (minSimilarity != null && resolvedMode != GoldenMode.ssim) {
      throw ArgumentError.value(
        minSimilarity,
        'minSimilarity',
        'only applies to GoldenMode.ssim (mode is ${resolvedMode.name})',
      );
    }
    if (colorTolerance != null && resolvedMode != GoldenMode.ssim) {
      throw ArgumentError.value(
        colorTolerance,
        'colorTolerance',
        'only applies to GoldenMode.ssim (mode is ${resolvedMode.name})',
      );
    }
    // Only the settings the resolved mode uses are validated: suite defaults
    // for another mode must not break this comparison.
    final resolvedThreshold = threshold ?? defaults.threshold;
    final resolvedMinSimilarity = minSimilarity ?? defaults.minSimilarity;
    final resolvedColorTolerance = colorTolerance ?? defaults.colorTolerance;
    switch (resolvedMode) {
      case GoldenMode.exact:
        break;
      case GoldenMode.pixel:
        _ratio(resolvedThreshold, 'threshold');
      case GoldenMode.ssim:
        _ratio(resolvedMinSimilarity, 'minSimilarity');
        if (!resolvedColorTolerance.isFinite ||
            resolvedColorTolerance < 0 ||
            resolvedColorTolerance > 255) {
          throw ArgumentError.value(
            resolvedColorTolerance,
            'colorTolerance',
            'must be between 0 and 255',
          );
        }
    }
    final regions = ignoreRegions ?? defaults.ignoreRegions;
    for (final region in regions) {
      if (!region.isFinite ||
          region.left < 0 ||
          region.top < 0 ||
          region.isEmpty) {
        throw ArgumentError.value(
          region,
          'ignoreRegions',
          'must be finite, non-empty and have non-negative coordinates',
        );
      }
    }
    return ResolvedGoldenOptions._(
      mode: resolvedMode,
      threshold: resolvedThreshold,
      minSimilarity: resolvedMinSimilarity,
      colorTolerance: resolvedColorTolerance,
      ignoreRegions: List.unmodifiableOf(regions),
    );
  }

  /// Comparison mode.
  final GoldenMode mode;

  /// Pixel threshold (used only for [GoldenMode.pixel]).
  final double threshold;

  /// SSIM threshold (used only for [GoldenMode.ssim]).
  final double minSimilarity;

  /// Envelope tolerance (used only for [GoldenMode.ssim]).
  final double colorTolerance;

  /// Regions excluded from the comparison.
  final List<Rect> ignoreRegions;

  /// Short human-readable description, e.g. `ssim ≥ 0.990`.
  String describe() => switch (mode) {
    GoldenMode.exact => 'exact',
    GoldenMode.pixel => 'pixel ≤ ${_percent(threshold)}',
    GoldenMode.ssim =>
      'ssim ≥ ${minSimilarity.toStringAsFixed(3)}, '
          'color ±${colorTolerance.toStringAsFixed(0)}',
  };

  /// JSON options understood by the native `gleon_compare`.
  ///
  /// Regions are expanded outwards to whole pixels.
  Map<String, Object?> toNativeJson() => {
    'mode': mode.name,
    if (mode == GoldenMode.pixel) 'threshold': threshold,
    if (mode == GoldenMode.ssim) ...{
      'min_similarity': minSimilarity,
      'color_tolerance': colorTolerance,
    },
    if (ignoreRegions.isNotEmpty)
      'masks': [
        for (final r in ignoreRegions)
          {
            'x': r.left.floor(),
            'y': r.top.floor(),
            'width': r.right.ceil() - r.left.floor(),
            'height': r.bottom.ceil() - r.top.floor(),
          },
      ],
  };
}

void _ratio(double value, String name) {
  if (value.isNaN || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be between 0.0 and 1.0');
  }
}

String _percent(double ratio) => '${(ratio * 100).toStringAsFixed(2)}%';
