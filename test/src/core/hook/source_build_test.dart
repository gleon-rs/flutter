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
      // Names the variables the hook never sees.
      throwsState(
        allOf(
          contains('`cargo` was not found'),
          contains(SourceBuild.hookEnvironmentHint),
        ),
      ),
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

  test('workspace-inherited and single-quoted paths are followed', () {
    final root = Uri.directory(fakeCheckout());
    final manifests = {
      'Cargo.toml':
          '[workspace.dependencies]\n'
          "gleon-model = { path = 'gleon-model' }\n"
          'outside = { path = "../outside" }\n',
      '${SourceBuild.crate}/Cargo.toml': 'gleon-model = { workspace = true }',
      'gleon-model/Cargo.toml': "gleon-engine = { path = '../gleon-engine' }",
      '../outside/Cargo.toml': '[package]',
    };
    for (final MapEntry(key: path, value: content) in manifests.entries) {
      File.fromUri(root.resolve(path))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    final inputs = SourceBuild.inputs(root);

    expect(
      inputs,
      containsAll([
        root.resolve('gleon-model/src/rules.rs'),
        root.resolve('gleon-engine/src/lib.rs'),
      ]),
    );
    // A crate outside the checkout is not an input of it.
    expect(inputs, isNot(contains(root.resolve('../outside/Cargo.toml'))));
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

    // Cargo's dep-info names every file it compiled: a crate-root `build.rs`
    // and `include_bytes!` data too, which no glob of `src/` sees; files
    // outside the checkout (the standard library) are no inputs of it.
    test('depends on what cargo compiled inside the checkout', () async {
      final root = fakeCheckout();
      // The standard library, and a sibling reached through `..`: outside.
      final outside = [
        '${tempPath()}/rustlib/src/core/lib.rs',
        '$root/../gleon-sibling/src/lib.rs',
      ];
      for (final file in [
        '$root/gleon-ffi/build.rs',
        '$root/gleon-ffi/data/a table.bin',
        ...outside,
      ]) {
        File(file)
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
      final cargo = FakeCargo(
        compiled: [
          '$root/gleon-ffi/build.rs',
          '$root/gleon-ffi/src/lib.rs',
          // As rustc joins an `include_bytes!` path to its source file.
          '$root/gleon-ffi/src/../data/a table.bin',
          ...outside,
        ],
      );

      final built = await SourceBuild.run(
        repoRoot: .file(root),
        targetDir: .directory('${tempPath()}/cargo'),
        target: .linuxX64,
        environment: cargoEnvironment(),
        runProcess: cargo.run,
      );
      final checkout = Uri.directory(root);
      expect(
        built.dependencies,
        containsAll([
          checkout.resolve('Cargo.toml'),
          // The versions of the registry crates, whose sources lie outside.
          checkout.resolve('Cargo.lock'),
          checkout.resolve('gleon-ffi/Cargo.toml'),
          checkout.resolve('gleon-ffi/build.rs'),
          checkout.resolve('gleon-ffi/src/lib.rs'),
          Uri.file('$root/gleon-ffi/data/a table.bin'),
        ]),
      );
      expect(
        built.dependencies,
        isNot(contains(checkout.resolve('gleon-model/src/rules.rs'))),
        reason: 'not compiled: the dep-info replaces the glob of src/',
      );
      for (final file in outside) {
        expect(
          built.dependencies,
          isNot(contains(Uri.file(file))),
          reason: file,
        );
      }
    });

    // Cargo runs in the physical directory of a checkout named through a
    // symbolic link, so its dep-info names the files under the resolved path.
    test('a checkout named through a symbolic link keeps its inputs', () async {
      final root = fakeCheckout();
      final link = Link('${tempPath()}/linked-checkout');
      try {
        link.createSync(root);
      } on FileSystemException catch (error) {
        // Windows without the privilege to create symbolic links.
        markTestSkipped('symbolic links cannot be created here: $error');

        return;
      }
      final physical = Directory(root).resolveSymbolicLinksSync();
      File('$root/gleon-ffi/build.rs')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      final cargo = FakeCargo(
        compiled: [
          '$physical/gleon-ffi/build.rs',
          '$physical/gleon-ffi/src/lib.rs',
        ],
      );

      final built = await SourceBuild.run(
        repoRoot: .directory(link.path),
        targetDir: .directory('${tempPath()}/cargo'),
        target: .linuxX64,
        environment: cargoEnvironment(),
        runProcess: cargo.run,
      );
      expect(
        built.dependencies,
        contains(Uri.file('$physical/gleon-ffi/build.rs')),
      );
    });

    // `build.dep-info-basedir` makes cargo write paths relative to a
    // directory of its config: without knowing it, every input is tracked.
    test('relative dep-info paths fall back to every input', () async {
      final root = fakeCheckout();
      final cargo = FakeCargo(compiled: ['gleon-ffi/src/lib.rs']);

      final built = await SourceBuild.run(
        repoRoot: .file(root),
        targetDir: .directory('${tempPath()}/cargo'),
        target: .linuxX64,
        environment: cargoEnvironment(),
        runProcess: cargo.run,
      );
      expect(
        built.dependencies,
        unorderedEquals(SourceBuild.inputs(.directory(root))),
      );
    });

    // A dep-info that names no file (another format) tracks every input
    // instead of the manifests alone.
    test('a dep-info naming no file falls back to every input', () async {
      final root = fakeCheckout();
      final built = await SourceBuild.run(
        repoRoot: .file(root),
        targetDir: .directory('${tempPath()}/cargo'),
        target: .linuxX64,
        environment: cargoEnvironment(),
        runProcess: FakeCargo(compiled: []).run,
      );
      expect(
        built.dependencies,
        unorderedEquals(SourceBuild.inputs(.directory(root))),
      );
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
