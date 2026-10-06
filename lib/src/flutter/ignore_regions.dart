import 'dart:ui' show Rect;

import '../core/compare/pixel_region.dart';

/// Converts the `ignoreRegions` of a matcher call into engine masks.
abstract final class IgnoreRegions {
  /// The largest pixel coordinate a region may reach.
  static const maxCoordinate = 0xFFFFFFFF;

  /// Validates [regions] (pixels of the golden PNG, origin top-left) and
  /// expands each outwards to whole pixels.
  ///
  /// Throws an [ArgumentError] for a region that is not finite, is empty, has
  /// negative coordinates or reaches beyond [maxCoordinate] (the engine takes
  /// unsigned 32-bit pixels; larger values would silently wrap around).
  static List<PixelRegion> toMasks(List<Rect> regions) =>
      .unmodifiable([for (final region in regions) _toMask(region)]);

  static PixelRegion _toMask(Rect region) {
    final Rect(:bottom, :isEmpty, :isFinite, :left, :right, :top) = region;
    if (!isFinite ||
        left < 0 ||
        top < 0 ||
        isEmpty ||
        right > maxCoordinate ||
        bottom > maxCoordinate) {
      throw ArgumentError.value(
        region,
        'ignoreRegions',
        'must be finite, non-empty and have coordinates between 0 and '
            '$maxCoordinate',
      );
    }

    return .outwards(left: left, top: top, right: right, bottom: bottom);
  }
}
