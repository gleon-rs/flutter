import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs each golden test of a file against a private copy of the package
/// goldens under `test/goldens/`, through Flutter's own [LocalFileComparator].
///
/// `flutter test` runs test files in parallel processes, and failure
/// artifacts are named after the golden (`failures/swatch_testImage.png`), so
/// files sharing a directory would race on them. The sandbox also keeps the
/// repository clean: failures and `--update-goldens` writes land in a temp
/// directory that is deleted after each test.
abstract final class GoldenSandbox {
  /// The package goldens, relative to the package root (`flutter test`'s
  /// working directory).
  static const source = 'test/goldens';

  static Directory? _dir;

  /// The sandbox of the running test (the comparator's basedir).
  static Directory get dir =>
      _dir ?? (throw StateError('call GoldenSandbox.install() in main()'));

  /// Where failure artifacts of the running test are written.
  static Directory get failures => .new('${dir.path}/failures');

  /// Registers `setUp`/`tearDown` that create and remove the sandbox.
  static void install() {
    setUp(_create);
    tearDown(_delete);
  }

  static void _create() {
    final original = goldenFileComparator;
    if (original is! LocalFileComparator) {
      throw StateError("expected Flutter's default LocalFileComparator");
    }
    final sandbox = Directory.systemTemp.createTempSync('gleon_goldens_');
    final goldens = Directory(source);
    Directory('${sandbox.path}/goldens').createSync();
    for (final file in goldens.listSync().whereType<File>()) {
      if (file.uri.pathSegments.lastOrNull case final name?) {
        file.copySync('${sandbox.path}/goldens/$name');
      }
    }
    _dir = sandbox;
    goldenFileComparator = LocalFileComparator(
      sandbox.uri.resolve('sandbox_test.dart'),
    );
    addTearDown(() => goldenFileComparator = original);
  }

  static void _delete() {
    _dir?.deleteSync(recursive: true);
    _dir = null;
  }
}
