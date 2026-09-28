import 'package:meta/meta.dart';

import '../compare/golden_tolerance.dart';
import '../compare/mask_zone.dart';

/// Which screenshot rule of `.gleon/gleon.yaml` applies to a golden.
@immutable
sealed class GoldenRule {
  /// Base constructor of the variants.
  const GoldenRule();

  /// Parses a `gleon-model` `RuleMatch`, or returns null for another shape.
  static GoldenRule? fromNativeJson(Object? json) => switch (json) {
    {
      'index': final int index,
      'kind': 'matched',
      'masks': final List<Object?> masks,
      'name': final String name,
      'tolerance': final tolerance,
    } =>
      _matched(index, name, tolerance, masks),
    {'kind': 'excluded'} => const ExcludedRule(),
    {'kind': 'unmatched'} => const UnmatchedRule(),
    _ => null,
  };

  static MatchedRule? _matched(
    int index,
    String name,
    Object? tolerance,
    List<Object?> masks,
  ) {
    final parsedTolerance = GoldenTolerance.fromNativeJson(tolerance);
    final parsedMasks = [
      for (final mask in masks) MaskZone.fromNativeJson(mask),
    ];
    if (parsedTolerance == null || parsedMasks.contains(null)) return null;

    return MatchedRule(
      index: index,
      name: name,
      tolerance: parsedTolerance,
      masks: .unmodifiable(parsedMasks.nonNulls),
    );
  }
}

/// `screenshots[index]` applies.
final class MatchedRule extends GoldenRule {
  /// Creates the rule.
  const MatchedRule({
    required this.index,
    required this.name,
    required this.tolerance,
    required this.masks,
  });

  /// Index of the rule in `screenshots`.
  final int index;

  /// Canonical gleon test name of the golden (the case report name).
  final String name;

  /// The rule's tolerance.
  final GoldenTolerance tolerance;

  /// The rule's mask zones for this golden.
  final List<MaskZone> masks;
}

/// Matched by `exclude` (or inside a directory the CLI never scans): the rule
/// does not apply and no case report is written.
final class ExcludedRule extends GoldenRule {
  /// Creates the rule.
  const ExcludedRule();
}

/// No rule includes the golden, so the CLI does not track it: compared like
/// an excluded golden.
final class UnmatchedRule extends GoldenRule {
  /// Creates the rule.
  const UnmatchedRule();
}
