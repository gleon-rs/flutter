import 'dart:ui' show Rect;

import '../core/compare/pixel_region.dart';

/// Converts the `ignoreRegions` of a matcher call into engine masks.
abstract final class IgnoreRegions {
  /// Validates [regions] (pixels of the golden PNG, origin top-left) and
  /// expands each outwards to whole pixels.
  ///
  /// Throws an [ArgumentError] for a region that is not finite, is empty or
  /// has negative coordinates.
  static List<PixelRegion> toMasks(List<Rect> regions) =>
      .unmodifiable([for (final region in regions) _toMask(region)]);

  static PixelRegion _toMask(Rect region) {
    final Rect(:bottom, :isEmpty, :isFinite, :left, :right, :top) = region;
    if (!isFinite || left < 0 || top < 0 || isEmpty) {
      throw ArgumentError.value(
        region,
        'ignoreRegions',
        'must be finite, non-empty and have non-negative coordinates',
      );
    }
    final x = left.floor();
    final y = top.floor();

    return .new(x: x, y: y, width: right.ceil() - x, height: bottom.ceil() - y);
  }
}
