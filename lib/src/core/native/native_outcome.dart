// The outcome and its two code enums mirror one `GleonSummary`.
// ignore_for_file: prefer-single-declaration-per-file

import 'package:meta/meta.dart';

/// What a native call reports: the verdict and the texts to show.
@immutable
final class NativeOutcome {
  /// Creates the outcome.
  const NativeOutcome(
    this.verdict, {
    required this.errorKind,
    required this.message,
    required this.console,
    required this.warning,
  });

  /// The verdict.
  final NativeVerdict verdict;

  /// The class of a [NativeVerdict.error]; [NativeErrorKind.none] otherwise.
  final NativeErrorKind errorKind;

  /// The complete test failure message; empty for a pass.
  final String message;

  /// The console line to print; empty unless metrics print one.
  final String console;

  /// Warnings to print, one per line; usually empty.
  final String warning;
}

/// Verdict of one native call, with its `u8` code in `gleon-ffi`.
enum NativeVerdict {
  /// Different image sizes.
  dimensionMismatch(3),

  /// Invalid input, config or I/O failure; never a pass.
  error(4),

  /// Byte-identical PNGs.
  identical(0),

  /// Within the tolerance.
  match(1),

  /// Beyond the tolerance.
  mismatch(2),

  /// The golden does not exist.
  missing(6),

  /// The golden was written (`--update-goldens`).
  updated(5);

  NativeVerdict(this.code);

  /// The code of `gleon-ffi`.
  final int code;

  /// The verdict of [code]; unknown codes are errors, never passes.
  static NativeVerdict of(int code) =>
      values.firstWhere((verdict) => verdict.code == code, orElse: () => error);

  /// Whether the test passes.
  bool get isPass => switch (this) {
    identical || match || updated => true,
    dimensionMismatch || error || missing || mismatch => false,
  };
}

/// Class of a failed native call, with its `u8` code in `gleon-ffi`.
enum NativeErrorKind {
  /// `.gleon/gleon.yaml`, a golden name or an environment variable
  /// (`GLEON_METRICS`, `GLEON_ARTIFACTS_DIR`, `GLEON_RUN_ID`) is invalid.
  config(2),

  /// An image could not be decoded, is over the analysis budget or could not
  /// be encoded.
  image(4),

  /// A bug in the native library (a caught panic).
  internal(5),

  /// This package broke the C contract.
  invalidInput(1),

  /// A file could not be read or written.
  io(3),

  /// The call did not fail.
  none(0);

  NativeErrorKind(this.code);

  /// The code of `gleon-ffi`.
  final int code;

  /// The kind of [code]; unknown codes are internal errors.
  static NativeErrorKind of(int code) =>
      values.firstWhere((kind) => kind.code == code, orElse: () => internal);

  /// Whether the error is a bug of gleon rather than of the test or its
  /// files: this package broke the C contract, or the native code panicked.
  bool get isBug => switch (this) {
    internal || invalidInput => true,
    config || image || io || none => false,
  };
}
