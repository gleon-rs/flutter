/// A download or verification failure of the native library with an
/// actionable message.
final class NativeDownloadException implements Exception {
  /// Creates the exception.
  const NativeDownloadException(this.message);

  /// Human-readable reason, including what to do about it.
  final String message;

  @override
  String toString() => 'gleon: $message';
}
