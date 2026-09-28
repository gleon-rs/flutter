import 'package:meta/meta.dart';

/// The integration that produced a candidate.
@immutable
final class CaseSource {
  /// Creates the source.
  const CaseSource({
    required this.tool,
    required this.toolVersion,
    this.renderer,
  });

  /// Integration name, e.g. `gleon_flutter`.
  final String tool;

  /// Integration version.
  final String toolVersion;

  /// Renderer identifier, e.g. `flutter-3.47.5`.
  final String? renderer;

  /// `{tool, tool_version, renderer?}`.
  Map<String, Object> toJson() => {
    'renderer': ?renderer,
    'tool': tool,
    'tool_version': toolVersion,
  };
}
