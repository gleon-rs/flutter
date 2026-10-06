import 'package:meta/meta.dart';

/// An axis-aligned rectangle in whole pixels of an image (origin top-left).
///
/// Used both for masks sent to the engine and for regions it reports.
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
  /// ([right], [bottom]), which must be finite: its edges rounded outwards.
  factory PixelRegion.outwards({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
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
