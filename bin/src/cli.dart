/// The command line of the maintainer scripts in `bin/`: flag values,
/// failures, help and the package they run in.
///
/// Only `dart:*` may be imported here (see `build_native.dart`).
library;

import 'dart:io';
import 'dart:isolate';

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
    stderr.writeln('$name: $message');
    exit(64);
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
  /// the sibling `../gleon` of [packageRoot]; absolute.
  static Directory gleonCheckout(String? flag, Uri packageRoot) => Directory(
    flag ??
        Platform.environment['GLEON_REPO'] ??
        packageRoot.resolve('../gleon').toFilePath(),
  ).absolute;

  /// The root of this package (the directory of its `pubspec.yaml`).
  Future<Uri> packageRoot() async {
    final lib = await Isolate.resolvePackageUri(.parse('package:gleon/'));
    if (lib == null) fail('run this from the gleon package directory.');

    return lib.resolve('../');
  }
}
