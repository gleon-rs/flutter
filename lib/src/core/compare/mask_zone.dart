import 'package:meta/meta.dart';

import 'pixel_region.dart';
import 'zone_length.dart';

/// A zone excluded from a comparison, in pixels of the golden or relative to
/// its size (the `Zone` of `gleon-model`, as written in `.gleon/gleon.yaml`).
@immutable
final class MaskZone {
  /// Creates a zone.
  const MaskZone({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// The zone of a whole-pixel [region].
  MaskZone.fromRegion(PixelRegion region)
    : this(
        x: region.x,
        y: region.y,
        width: PixelLength(region.width),
        height: PixelLength(region.height),
      );

  /// Left edge in pixels.
  final int x;

  /// Top edge in pixels.
  final int y;

  /// Width in pixels or percent of the image width.
  final ZoneLength width;

  /// Height in pixels or percent of the image height.
  final ZoneLength height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  /// Parses a `gleon-model` `Zone` with patterns, or returns null for another
  /// shape.
  static MaskZone? fromNativeJson(Object? json) {
    if (json case {
      'height': final height,
      'width': final width,
      'x': final int x,
      'y': final int y,
    }) {
      final parsedWidth = ZoneLength.fromNativeJson(width);
      final parsedHeight = ZoneLength.fromNativeJson(height);
      if (parsedWidth != null && parsedHeight != null) {
        return MaskZone(x: x, y: y, width: parsedWidth, height: parsedHeight);
      }
    }

    return null;
  }

  /// The `Zone` JSON understood by the native `gleon_compare` masks.
  Map<String, Object> toNativeJson() => {
    'height': height.toNativeJson(),
    'width': width.toNativeJson(),
    'x': x,
    'y': y,
  };

  @override
  bool operator ==(Object other) =>
      other is MaskZone &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  String toString() => '($x, $y) $width x $height';
}
