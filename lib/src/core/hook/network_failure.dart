/// A download that failed for the network (no connection, a timeout, a busy
/// or failing server after every retry), not for what it fetched: the build
/// may pass when tried again. The build hook reports it as an
/// infrastructure failure (`HookFailures.reporting`).
final class NetworkFailure extends StateError {
  /// Creates the failure [message].
  NetworkFailure(super.message);
}
