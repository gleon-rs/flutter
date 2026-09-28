import 'golden_tolerance.dart';

/// Decides which [GoldenTolerance] one comparison uses.
abstract final class ToleranceResolver {
  /// Priority: [requested] (the `tolerance` argument of the matcher call),
  /// then [configured] (the matching rule of `.gleon/gleon.yaml`), then
  /// [GoldenTolerance.exact].
  static GoldenTolerance resolve(
    GoldenTolerance? requested, {
    GoldenTolerance? configured,
  }) => requested ?? configured ?? const .exact();
}
