/// The stray home config of `bin/consumer_check.dart` (CI only).
library;

import 'dart:io';

import 'check_failure.dart';

/// An invalid `~/.gleon/gleon.yaml` for the run: the home directory is never
/// a workspace root, so it must change nothing for the app (which has no
/// `.git`). Refuses to touch an existing one.
final class StrayHomeConfig {
  const StrayHomeConfig._(this.file, {required this.isDirCreated});

  /// Writes the stray config of the home directory [home].
  factory StrayHomeConfig.write(String home) {
    final dir = Directory('$home/.gleon');
    final file = File('${dir.path}/gleon.yaml');
    if (file.existsSync()) {
      throw CheckFailure(
        '${file.path} exists; a stray config will not touch it.',
      );
    }
    final isDirCreated = !dir.existsSync();
    dir.createSync(recursive: true);
    file.writeAsStringSync('this is not: [a valid config\n');

    return StrayHomeConfig._(file, isDirCreated: isDirCreated);
  }

  /// The config written.
  final File file;

  /// Whether `~/.gleon` was created for it (and is removed with it).
  final bool isDirCreated;

  void remove() {
    if (file.existsSync()) file.deleteSync();
    if (isDirCreated && file.parent.existsSync()) {
      file.parent.deleteSync(recursive: true);
    }
  }
}
