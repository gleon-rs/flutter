import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/source_build.dart';

import '../../../helpers/fake_cargo.dart';

void main() {
  Directory? temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('gleon_source_'));
  tearDown(() => temp?.deleteSync(recursive: true));

  String tempPath() => (temp ?? .systemTemp).path;

  String cargoName() => Platform.isWindows ? 'cargo.exe' : 'cargo';

  /// A minimal gleon checkout layout (no Rust code needed); its path without
  /// a trailing separator, like user-defines resolve it.
  String fakeCheckout() {
    final root = '${tempPath()}/gleon';
    // No rust-toolchain.toml: optional workspace files are tracked only when
    // present.
    final files = {
      'Cargo.lock': '# lock',
      'Cargo.toml': '[workspace]',
      '${SourceBuild.crate}/Cargo.toml':
          'gleon-engine = { path = "../gleon-engine" }\n'
          'gleon-model = { path = "../gleon-model", features = ["x"] }\n',
      '${SourceBuild.crate}/src/lib.rs': '// Rust',
      'gleon-model/Cargo.toml': 'gleon-engine = { path = "../gleon-engine" }',
      'gleon-model/src/rules.rs': '// Rust',
      'gleon-engine/Cargo.toml': '[package]',
      'gleon-engine/src/lib.rs': '// Rust',
      // Not a dependency of the library: never tracked.
      'gleon-core/Cargo.toml': 'gleon-model = { path = "../gleon-model" }',
      'gleon-core/src/lib.rs': '// Rust',
    };
    for (final MapEntry(key: path, value: content) in files.entries) {
      File('$root/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    return root;
  }

  /// A cargo on `PATH` (never run: builds use [fakeRunner]).
  Map<String, String> cargoEnvironment() {
    final bin = Directory('${tempPath()}/bin')..createSync();
    File('${bin.path}/${cargoName()}').createSync();

    return {'PATH': bin.path};
  }

  Matcher throwsState(Matcher message) => throwsA(
    isA<StateError>().having((error) => error.message, 'message', message),
  );

  group('checkoutRoot', () {
    test('adds the trailing slash user-define paths lack', () {
      final root = fakeCheckout();

      expect(SourceBuild.checkoutRoot(.file(root)), Uri.directory(root));
      expect(SourceBuild.checkoutRoot(.directory(root)), Uri.directory(root));
    });

    test('names the user-define when the directory is no gleon checkout', () {
      expect(
        () => SourceBuild.checkoutRoot(.directory(tempPath())),
        throwsState(allOf(contains('`gleon_repo`'), contains('gleon-ffi'))),
      );
    });
  });

  group('findCargo', () {
    test('explains where it looked when cargo is missing', () {
      final empty = tempPath();
      expect(
        () => SourceBuild.findCargo({'HOME': empty, 'PATH': empty}),
        throwsState(
          allOf(
            contains('`cargo` was not found'),
            contains('$empty/.cargo/bin'),
            contains('`gleon_repo`'),
          ),
        ),
      );
    });

    test('finds cargo on PATH', () {
      final bin = '${tempPath()}/bin';
      final cargo = File('$bin${Platform.pathSeparator}${cargoName()}')
        ..createSync(recursive: true);

      expect(SourceBuild.findCargo({'PATH': bin}), cargo.path);
    });

    test('falls back to CARGO_HOME for IDE-launched processes', () {
      final home = '${tempPath()}/cargo_home';
      final cargo = File('$home/bin${Platform.pathSeparator}${cargoName()}')
        ..createSync(recursive: true);

      expect(SourceBuild.findCargo({'CARGO_HOME': home}), cargo.path);
    });
  });

  test('a build without cargo fails before running anything', () async {
    final empty = tempPath();
    final targetDir = Uri.directory('$empty/cargo');
    await expectLater(
      SourceBuild.run(
        repoRoot: .file(fakeCheckout()),
        targetDir: targetDir,
        target: .linuxX64,
        environment: {'HOME': empty, 'PATH': empty},
      ),
      throwsState(contains('`cargo` was not found')),
    );
    expect(Directory.fromUri(targetDir).existsSync(), isFalse);
  });

  test('tracks the library crate and every crate it reaches by path', () {
    final root = Uri.directory(fakeCheckout());
    final inputs = SourceBuild.inputs(root);

    expect(
      inputs,
      containsAll([
        root.resolve('Cargo.toml'),
        root.resolve('Cargo.lock'),
        root.resolve('gleon-ffi/src/lib.rs'),
        root.resolve('gleon-model/Cargo.toml'),
        root.resolve('gleon-model/src/rules.rs'),
        root.resolve('gleon-engine/src/lib.rs'),
      ]),
    );
    expect(inputs, isNot(contains(root.resolve('gleon-core/src/lib.rs'))));
    expect(inputs, isNot(contains(root.resolve('rust-toolchain.toml'))));
    expect(inputs.toSet(), hasLength(inputs.length), reason: 'no duplicates');
  });

  test('a cycle or a missing crate does not stop the traversal', () {
    final root = Uri.directory(fakeCheckout());
    File.fromUri(root.resolve('gleon-engine/Cargo.toml')).writeAsStringSync(
      'gleon-ffi = { path = "../gleon-ffi" }\n'
      'gone = { path = "../gone" }\n',
    );

    final inputs = SourceBuild.inputs(root);

    expect(inputs, contains(root.resolve('gleon-ffi/src/lib.rs')));
    // A missing file as a hook dependency would look changed on every run.
    expect(inputs, isNot(contains(root.resolve('gone/Cargo.toml'))));
  });

  group('run', () {
    Future<LibraryFiles> build(FakeCargo cargo) => SourceBuild.run(
      repoRoot: .file(fakeCheckout()),
      targetDir: .directory('${tempPath()}/cargo'),
      target: .linuxX64,
      environment: cargoEnvironment(),
      runProcess: cargo.run,
    );

    test('builds the requested target and reports its inputs', () async {
      final cargo = FakeCargo();
      final built = await build(cargo);

      expect(
        cargo.calls.singleOrNull,
        containsAllInOrder([
          'build',
          '--locked',
          '--target',
          'x86_64-unknown-linux-gnu',
        ]),
      );
      expect(
        built.library.path,
        endsWith('/cargo/x86_64-unknown-linux-gnu/release/libgleon_ffi.so'),
      );
      expect(built.dependencies, isNotEmpty);
    });

    test('a failing cargo is an error with its output', () async {
      await expectLater(
        build(FakeCargo(exitCode: 101)),
        throwsA(
          isA<ProcessException>()
              .having((error) => error.errorCode, 'exit code', 101)
              .having(
                (error) => error.message,
                'message',
                contains('out\nerr'),
              ),
        ),
      );
    });

    test('a successful cargo without the library is an error', () async {
      await expectLater(
        build(FakeCargo(isWritingLibrary: false)),
        throwsState(contains('cargo succeeded but')),
      );
    });
  });
}
