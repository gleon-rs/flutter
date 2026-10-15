/// Why a check of `bin/consumer_check.dart` failed.
library;

/// A check of the consumer that did not hold: what [message] says.
final class CheckFailure implements Exception {
  /// Creates the failure [message].
  const CheckFailure(this.message);

  /// Why the check failed.
  final String message;

  @override
  String toString() => message;
}

/// Throws a [CheckFailure] of [reason] unless [isMet].
void check(String reason, {required bool isMet}) {
  if (!isMet) throw CheckFailure('check failed: $reason');
}
