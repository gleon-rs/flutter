import 'package:meta/meta.dart';

/// An axis-aligned rectangle in whole pixels of an image (origin top-left).
///
/// Masks and text regions sent to the engine.
@immutable
@pragma('vm:deeply-immutable')
final class PixelRegion {
  /// Creates a region.
  const PixelRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// The whole pixels covering the rectangle from ([left], [top]) to
  /// ([right], [bottom]): its edges rounded outwards.
  ///
  /// The edges must be finite and non-negative (asserted): callers validate
  /// them (`ignoreRegions`) or clip them to the image (text regions).
  factory PixelRegion.outwards({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    assert(
      [left, top, right, bottom].every((edge) => edge.isFinite && edge >= 0),
      'edges must be finite and non-negative: $left, $top, $right, $bottom',
    );
    final x = left.floor();
    final y = top.floor();

    return .new(x: x, y: y, width: right.ceil() - x, height: bottom.ceil() - y);
  }

  /// Left edge.
  final int x;

  /// Top edge.
  final int y;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  bool operator ==(Object other) =>
      other is PixelRegion &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  String toString() => '($x, $y) ${width}x${height}px';
}
