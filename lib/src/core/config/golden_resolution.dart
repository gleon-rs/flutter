import 'dart:convert';

import 'package:meta/meta.dart';

import 'golden_rule.dart';
import 'metrics_settings.dart';

/// How `.gleon/gleon.yaml` applies to one golden, as resolved by the native
/// `gleon_config_resolve` (the same rule selection as the gleon CLI).
@immutable
sealed class GoldenResolution {
  /// Base constructor of the variants.
  const GoldenResolution();

  /// Parses the resolve response with patterns; anything off-contract becomes
  /// a [GoldenResolutionError].
  static GoldenResolution fromNativeJson(Object? json) => switch (json) {
    {
      'kind': 'resolved',
      'metrics': {
        'console': final bool isConsoleEnabled,
        'enabled': final bool isEnabled,
      },
      'platform': final Map<String, Object?> platform,
      'policy_version': final int policyVersion,
      'rule': final rule,
    } =>
      _resolved(
        rule,
        metrics: MetricsSettings(
          isEnabled: isEnabled,
          isConsoleEnabled: isConsoleEnabled,
        ),
        platform: platform,
        policyVersion: policyVersion,
      ),
    {'error': final String message, 'kind': 'error'} => GoldenResolutionError(
      message,
    ),
    _ => GoldenResolutionError(
      'unexpected resolve response: ${jsonEncode(json)}',
    ),
  };

  static GoldenResolution _resolved(
    Object? rule, {
    required MetricsSettings metrics,
    required Map<String, Object?> platform,
    required int policyVersion,
  }) {
    final parsed = GoldenRule.fromNativeJson(rule);

    return parsed == null
        ? GoldenResolutionError(
            'unexpected rule in the resolve response: ${jsonEncode(rule)}',
          )
        : ResolvedGolden(
            rule: parsed,
            metrics: metrics,
            platform: platform,
            policyVersion: policyVersion,
          );
  }
}

/// The config is valid and the golden was resolved.
final class ResolvedGolden extends GoldenResolution {
  /// Creates the resolution.
  const ResolvedGolden({
    required this.rule,
    required this.metrics,
    required this.platform,
    required this.policyVersion,
  });

  /// The applicable screenshot rule.
  final GoldenRule rule;

  /// The `metrics:` settings, `GLEON_METRICS` applied.
  final MetricsSettings metrics;

  /// The host platform (`{"os": ..., "arch": ...}`), named like the CLI.
  final Map<String, Object?> platform;

  /// Version of the engine's tolerant (SSIM) decision policy.
  final int policyVersion;

  /// The matching rule, or null for excluded and unmatched goldens.
  MatchedRule? get matched => switch (rule) {
    final MatchedRule hit => hit,
    ExcludedRule() || UnmatchedRule() => null,
  };

  /// Whether a case report is recorded: metrics are enabled and the CLI
  /// tracks this golden (a rule matches).
  bool get shouldRecordCase => metrics.isEnabled && matched != null;
}

/// Invalid config, golden path or `GLEON_METRICS` value.
final class GoldenResolutionError extends GoldenResolution {
  /// Creates the error.
  const GoldenResolutionError(this.message);

  /// The parser's message.
  final String message;
}
