import 'dart:io';

import 'package:meta/meta.dart';

import '../compare/golden_tolerance.dart';
import '../compare/mask_zone.dart';
import 'gleon_config_exception.dart';
import 'gleon_session.dart';
import 'golden_resolution.dart';
import 'golden_rule.dart';

/// What one comparison uses (tolerance, masks) and whether it records a case.
@immutable
final class GoldenPlan {
  /// Creates the plan.
  const GoldenPlan({
    required this.tolerance,
    required this.masks,
    required this.hasWorkspace,
    this.resolved,
    this.goldenPath,
  });

  /// Plans the comparison of [golden] (an existing file) in [session]: the
  /// call's [tolerance] beats the `.gleon/gleon.yaml` rule, which beats exact;
  /// the call's [masks] add to the rule's.
  ///
  /// Throws a [GleonConfigException] for an invalid config or golden name.
  factory GoldenPlan.of(
    GleonSession session,
    File golden, {
    GoldenTolerance? tolerance,
    List<MaskZone> masks = const [],
  }) {
    final workspace = session.workspace;
    switch (session.resolve(golden)) {
      case null:
        return GoldenPlan(
          tolerance: tolerance ?? const .exact(),
          masks: masks,
          hasWorkspace: workspace != null,
        );

      case GoldenResolutionError(:final message):
        throw GleonConfigException(
          workspace?.configFile.path ?? '.gleon/gleon.yaml',
          message,
        );

      case final ResolvedGolden resolved:
        final matched = switch (resolved.rule) {
          final MatchedRule rule => rule,
          ExcludedRule() || UnmatchedRule() => null,
        };

        return GoldenPlan(
          tolerance: tolerance ?? matched?.tolerance ?? const .exact(),
          masks: .unmodifiable([...masks, ...?matched?.masks]),
          hasWorkspace: true,
          resolved: resolved,
          goldenPath: workspace?.relativePath(golden),
        );
    }
  }

  /// The effective tolerance.
  final GoldenTolerance tolerance;

  /// The effective masks: the call's, then the rule's.
  final List<MaskZone> masks;

  /// Whether a `.gleon/gleon.yaml` workspace exists.
  final bool hasWorkspace;

  /// The golden's resolution, when it lies in the workspace.
  final ResolvedGolden? resolved;

  /// The golden's path relative to the workspace root.
  final String? goldenPath;
}
