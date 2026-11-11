/// The consumer app of `bin/consumer_check.dart`: this package copied as a
/// consumer gets it, and a fresh app with a golden test of a number. Only
/// `dart:*` and this package may be imported here (see `build_native.dart`).
library;

import 'dart:io';

import 'package:gleon/src/core/hook/native_target.dart';

/// The golden the consumer app records and compares.
const consumerGolden = 'goldens/number.png';

/// A proxy nothing listens on: every download fails at once.
const deadProxy = 'http://127.0.0.1:9';

/// The entries of the package root a consumer never gets (top level only:
/// `lib/src/core/native/` is code), besides hidden ones ([isHidden]):
/// everything else `.pubignore` leaves out there (a test keeps them in sync),
/// and what the hook needs not (`example/`, `test/`, `native/` but its pin).
const notShipped = {
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

/// Whether [dir] is [root] or lies inside it, both existing, compared by
/// their resolved paths (symbolic links and `..`), whole segments, and
/// without case on Windows: a copy of [root] there would copy itself.
bool isWithin(Directory dir, Directory root) =>
    _resolvedPath(dir).startsWith(_resolvedPath(root));

/// The path of [dir] as [isWithin] compares it: resolved, ending in `/`.
String _resolvedPath(Directory dir) {
  final path = Directory(dir.resolveSymbolicLinksSync()).uri.path;

  return Platform.isWindows ? path.toLowerCase() : path;
}

/// Whether [name] is hidden: pub leaves such entries out of the archive at
/// every level (`.dart_tool`, `.git`, `.fvm`, `.DS_Store`).
bool isHidden(String name) => name.startsWith('.');

/// Whether [copyPackage] copies the entry [name] ([isRoot]: of the package
/// root, where [notShipped] applies).
bool _isShipped(String name, {required bool isRoot}) =>
    !isHidden(name) && (!isRoot || !notShipped.contains(name));

/// Copies this package [from] its root into [into] without the directories a
/// consumer never gets: of `native/` only the pin, as in a git checkout of
/// the package (no library, so the hook has to download it). Hidden entries
/// and symbolic links are left out at every level: a link may lead anywhere
/// (FVM's `.fvm/flutter_sdk` is a whole Flutter SDK).
void copyPackage(Directory from, Directory into) {
  final pin = File.fromUri(NativeTarget.pinFile(from.uri));
  if (pin.existsSync()) {
    File.fromUri(NativeTarget.pinFile(into.uri))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(pin.readAsBytesSync());
  }
  final pending = [(from, into)];
  while (pending.isNotEmpty) {
    final (source, destination) = pending.removeLast();
    destination.createSync(recursive: true);
    final isRoot = source.path == from.path;
    // Not following links: a link is listed as a Link, and skipped below.
    final shipped = source
        .listSync(followLinks: false)
        .where((entry) => _isShipped(nameOf(entry), isRoot: isRoot));
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
/// test is written without dot shorthands; Material comes from `material_ui`,
/// as in apps that `flutter create` makes.
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
  material_ui: ^1.1.0

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
import 'package:gleon/gleon.dart';
import 'package:material_ui/material_ui.dart';

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
