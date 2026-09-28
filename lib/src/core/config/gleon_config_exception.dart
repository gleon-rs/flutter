/// An invalid `.gleon/gleon.yaml`, golden path or `GLEON_METRICS` value.
final class GleonConfigException implements Exception {
  /// Creates the exception for the config at [configPath].
  const GleonConfigException(this.configPath, this.message);

  /// Path of the `.gleon/gleon.yaml` in use.
  final String configPath;

  /// The parser's message.
  final String message;

  @override
  String toString() => 'gleon: $configPath: $message';
}
