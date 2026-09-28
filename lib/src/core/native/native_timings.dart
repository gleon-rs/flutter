import 'package:meta/meta.dart';

/// Time spent in the native library, in microseconds.
@immutable
final class NativeTimings {
  /// Creates the timings.
  const NativeTimings({
    required this.decodeMicros,
    required this.compareMicros,
    required this.encodeMicros,
  });

  /// Decoding both PNGs.
  final int decodeMicros;

  /// Masking and comparing.
  final int compareMicros;

  /// Encoding the diff PNG (mismatches only).
  final int encodeMicros;

  @override
  int get hashCode => Object.hash(decodeMicros, compareMicros, encodeMicros);

  /// The whole native call in milliseconds.
  double get totalMilliseconds =>
      (decodeMicros + compareMicros + encodeMicros) / 1000;

  /// Parses `{decode, compare, encode}`, or returns null for another shape.
  static NativeTimings? fromJson(Object? json) => switch (json) {
    {
      'compare': final int compareMicros,
      'decode': final int decodeMicros,
      'encode': final int encodeMicros,
    } =>
      .new(
        decodeMicros: decodeMicros,
        compareMicros: compareMicros,
        encodeMicros: encodeMicros,
      ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is NativeTimings &&
      other.decodeMicros == decodeMicros &&
      other.compareMicros == compareMicros &&
      other.encodeMicros == encodeMicros;
}
