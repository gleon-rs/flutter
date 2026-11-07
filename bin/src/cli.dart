/// The command line of the maintainer scripts in `bin/`: flag values,
/// failures, help and the package they run in.
///
/// Only `dart:*` and this package may be imported here (see
/// `build_native.dart`).
library;

import 'dart:io';
import 'dart:isolate';

import 'package:gleon/src/core/hook/source_build.dart';

/// The command line of one maintainer script.
final class Cli {
  /// The script [name] (the prefix of its failures) and its [usage].
  const Cli(this.name, this.usage);

  /// The script name, e.g. `build_native`.
  final String name;

  /// The help text.
  final String usage;

  /// Prints [message] and exits with 64.
  Never fail(String message) {
    report(message);
    exit(64);
  }

  /// Prints [message] and sets the exit code to 64 without exiting, so
  /// cleanup still runs (`exit` skips `finally` blocks).
  void report(String message) {
    stderr.writeln('$name: $message');
    exitCode = 64;
  }

  /// [fail] with [message] followed by the [usage].
  Never failUsage(String message) => fail('$message\n\n$usage');

  /// Prints the [usage] and exits successfully.
  Never help() {
    stdout.write(usage);
    exit(0);
  }

  /// The value following the flag that [rest] is at.
  String value(Iterator<String> rest) {
    final flag = rest.current;

    return rest.moveNext()
        // ignore: use-existing-variable, `moveNext` advanced to the value.
        ? rest.current
        : failUsage('$flag needs a value.');
  }

  /// The gleon checkout: [flag] (`--gleon-repo`), else `$GLEON_REPO`, else
  /// the sibling `../gleon` of [packageRoot]; absolute. Fails unless it is
  /// one ([SourceBuild.isCheckout]).
  Directory gleonCheckout(String? flag, Uri packageRoot) {
    // The failure names where the path came from: a stale `$GLEON_REPO` is
    // fixed there, not by passing the flag on every run.
    final (path, source) = switch ((flag, Platform.environment['GLEON_REPO'])) {
      (final String flag, _) => (flag, '--gleon-repo'),
      (null, final String env) => (env, r'$GLEON_REPO'),
      (null, null) => (
        packageRoot.resolve('../gleon').toFilePath(),
        'the sibling of this package',
      ),
    };
    final checkout = Directory(path).absolute;
    if (!SourceBuild.isCheckout(checkout.uri)) {
      fail(
        '${checkout.path} ($source) is not a gleon checkout; pass one with '
        '--gleon-repo.',
      );
    }

    return checkout;
  }

  /// The root of this package (the directory of its `pubspec.yaml`).
  Future<Uri> packageRoot() async {
    final lib = await Isolate.resolvePackageUri(.parse('package:gleon/'));
    if (lib == null) fail('run this from the gleon package directory.');

    return lib.resolve('../');
  }
}
