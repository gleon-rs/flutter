import 'package:meta/meta.dart';

/// The `metrics:` section of `.gleon/gleon.yaml`, `GLEON_METRICS` applied.
@immutable
final class MetricsSettings {
  /// Creates the settings.
  const MetricsSettings({
    required this.isEnabled,
    required this.isConsoleEnabled,
  });

  /// Whether a case report is recorded per golden.
  final bool isEnabled;

  /// Whether one line per golden is printed while [isEnabled].
  final bool isConsoleEnabled;
}
