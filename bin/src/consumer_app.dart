/// The consumer app of `bin/consumer_check.dart`: this package copied as a
/// consumer gets it, and a fresh app with a golden test of a number. Only
/// `dart:*` and this package may be imported here (see `build_native.dart`).
library;

import 'dart:io';

/// The golden the consumer app records and compares.
const consumerGolden = 'goldens/number.png';

/// A proxy nothing listens on: every download fails at once.
const deadProxy = 'http://127.0.0.1:9';

/// The pin of the gleon commit a git checkout of the package carries in
/// `native/` (the pub.dev archive ships none), relative to the package root.
const nativePin = 'native/gleon_ref';

/// The entries of the package root a consumer never gets (top level only:
/// `lib/src/core/native/` is code): everything `.pubignore` leaves out there
/// (a test keeps them in sync), and what the hook needs not (`example/`,
/// `test/`, `native/` but its pin).
const notShipped = {
  '.antigravity',
  '.dart_tool',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  '.git',
  '.github',
  '.packages',
  'CLAUDE.local.md',
  'benchmark',
  'bin',
  'build',
  'coverage',
  'dist',
  'example',
  'native',
  'pubspec.lock',
  'test',
};

/// [path] (a `PATH` of [separator]-separated directories) without the
/// directories that hold a Rust toolchain (`cargo`, `rustc`, `rustup`, as
/// [holds] tells): the hook must never need one. By what a directory holds,
/// not by its name (Homebrew puts cargo into `/opt/homebrew/bin`); one that
/// holds Flutter too stays, and the check relies on no source build having
/// run there.
String pathWithoutRust(
  String path, {
  required String separator,
  required bool Function(String dir, String tool) holds,
}) => path
    .split(separator)
    .where(
      (dir) =>
          holds(dir, 'flutter') ||
          !const ['cargo', 'rustc', 'rustup'].any((tool) => holds(dir, tool)),
    )
    .join(separator);

/// Copies this package [from] its root into [into] without the directories a
/// consumer never gets: of `native/` only the pin, as in a git checkout of
/// the package (no library, so the hook has to download it).
void copyPackage(Directory from, Directory into) {
  final pin = File('${from.path}/$nativePin');
  if (pin.existsSync()) {
    File('${into.path}/$nativePin')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(pin.readAsBytesSync());
  }
  final pending = [(from, into)];
  while (pending.isNotEmpty) {
    final (source, destination) = pending.removeLast();
    destination.createSync(recursive: true);
    final isRoot = source.path == from.path;
    final shipped = source.listSync().where(
      (entry) => !isRoot || !notShipped.contains(nameOf(entry)),
    );
    for (final entry in shipped) {
      final target = '${destination.path}/${nameOf(entry)}';
      switch (entry) {
        case final Directory dir:
          pending.add((dir, Directory(target)));

        case final File file:
          file.copySync(target);

        case _:
          break;
      }
    }
  }
}

/// The last path segment of [entry], read from its URI: `/`-separated on
/// every OS (a Windows path may mix `\` and `/`).
String nameOf(FileSystemEntity entry) => entry.uri.pathSegments.lastWhere(
  (segment) => segment.isNotEmpty,
  orElse: () => entry.path,
);

/// Writes the consumer app into [app]: gleon from [package], the library from
/// [releaseUrl], a golden test of a number with the app's real fonts and no
/// `.gleon/gleon.yaml`. Its language version is 3.0, as in most apps, so the
/// test is written without dot shorthands.
void writeConsumerApp(
  Directory app, {
  required Directory package,
  required Uri releaseUrl,
}) {
  Directory('${app.path}/test').createSync(recursive: true);
  File('${app.path}/pubspec.yaml').writeAsStringSync('''
name: consumer
description: A consumer of gleon, as pub.dev users meet it.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.0.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  gleon:
    path: ${package.path}

flutter:
  uses-material-design: true

hooks:
  user_defines:
    gleon:
      release_url: $releaseUrl
''');
  File('${app.path}/test/flutter_test_config.dart').writeAsStringSync('''
import 'dart:async';

import 'package:gleon/gleon.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts();
  await testMain();
}
''');
  File('${app.path}/test/number_test.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:gleon/gleon.dart';

import 'number.dart';

void main() {
  testWidgets('the number matches its golden', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text(number, style: TextStyle(fontSize: 48))),
        ),
      ),
    );
    await expectLater(find.byType(Scaffold), matchesGoldenFile('$consumerGolden'));
  });
}
''');
  writeNumber(app, '42');
}

/// The number the consumer app shows.
void writeNumber(Directory app, String number) =>
    File('${app.path}/test/number.dart').writeAsStringSync(
      "/// The number of the golden.\nconst number = '$number';\n",
    );
