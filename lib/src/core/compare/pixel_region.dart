import 'package:meta/meta.dart';

/// An axis-aligned rectangle in whole pixels of an image (origin top-left).
///
/// Used both for masks sent to the engine and for regions it reports.
@immutable
final class PixelRegion {
  /// Creates a region.
  const PixelRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

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

  /// Parses an engine `Region` (`{x, y, width, height}`) with patterns, or
  /// returns null for another shape.
  static PixelRegion? fromNativeJson(Object? json) => switch (json) {
    {
      'height': final int height,
      'width': final int width,
      'x': final int x,
      'y': final int y,
    } =>
      .new(x: x, y: y, width: width, height: height),
    _ => null,
  };

  /// The engine `Region` JSON.
  Map<String, int> toNativeJson() => {
    'height': height,
    'width': width,
    'x': x,
    'y': y,
  };

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
