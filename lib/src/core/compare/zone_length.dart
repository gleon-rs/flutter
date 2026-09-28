import 'package:meta/meta.dart';

/// A zone extent: whole pixels or a percentage of the image size (the
/// `Dimension` of `gleon-model`).
@immutable
sealed class ZoneLength {
  /// Base constructor of the variants.
  const ZoneLength();

  static final _percentPattern = RegExp(r'^(\d+(?:\.\d+)?)\s*%$');

  /// Parses a pixel count or a `"NN%"` / `"NN"` string, as `gleon-model`
  /// serializes a `Dimension`.
  static ZoneLength? fromNativeJson(Object? json) => switch (json) {
    final int pixels => PixelLength(pixels),
    final String text => _parseText(text.trim()),
    _ => null,
  };

  /// The `Dimension` JSON of `gleon-model`: a pixel count or a percentage
  /// string.
  // ignore: no-object-declaration, the JSON value is an int or a String.
  Object toNativeJson();

  /// The length as shown in failure messages (`12px`, `50.0%`). One
  /// exhaustive switch, so a new variant cannot fall back to `Instance of ...`.
  @override
  String toString() => switch (this) {
    PixelLength(:final pixels) => '${pixels}px',
    PercentLength(:final percent) => '$percent%',
  };

  static ZoneLength? _parseText(String text) {
    final percent = _percentPattern.firstMatch(text)?.group(1);
    if (percent != null) return PercentLength(double.parse(percent));

    return switch (int.tryParse(text)) {
      final pixels? => PixelLength(pixels),
      null => null,
    };
  }
}

/// A length in whole pixels.
final class PixelLength extends ZoneLength {
  /// Creates the length.
  const PixelLength(this.pixels);

  /// Number of pixels.
  final int pixels;

  @override
  int get hashCode => pixels.hashCode;

  @override
  Object toNativeJson() => pixels;

  @override
  bool operator ==(Object other) =>
      other is PixelLength && other.pixels == pixels;
}

/// A length relative to the image size.
final class PercentLength extends ZoneLength {
  /// Creates the length.
  const PercentLength(this.percent);

  /// Percentage of the image size (0–100).
  final double percent;

  @override
  int get hashCode => percent.hashCode;

  @override
  Object toNativeJson() => '$percent%';

  @override
  bool operator ==(Object other) =>
      other is PercentLength && other.percent == percent;
}
