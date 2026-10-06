import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/source_build.dart';

import '../../bin/src/native_build.dart';

void main() {
  const target = NativeTarget.linuxX64;
  final NativeTarget(:assetName, :key, :libFileName) = target;
  const commit = '18bc3075e002360815ae856d0a854cb6a62fa5a5';

  Directory? temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('gleon_build_'));
  tearDown(() => temp?.deleteSync(recursive: true));

  String tempPath() => (temp ?? .systemTemp).path;

  group('install', () {
    File built() {
      final path = '${tempPath()}/cargo/$libFileName';
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('library');

      return .new(path);
    }

    File native(String name) => .new('${tempPath()}/package/native/$key/$name');

    Future<List<File>> install({String? dist}) => NativeBuild.install(
      built(),
      target,
      packageRoot: Directory('${tempPath()}/package').uri,
      builtFrom: commit,
      dist: dist,
    );

    test('writes the library, its stamp and the release asset', () async {
      final written = await install(dist: '${tempPath()}/dist');

      expect(native(libFileName).readAsStringSync(), 'library');
      expect(native('gleon_ref').readAsStringSync(), '$commit\n');
      expect(
        File('${tempPath()}/dist/$assetName').readAsStringSync(),
        'library',
      );
      expect(
        [for (final file in written) file.uri.pathSegments.lastOrNull],
        [libFileName, assetName],
      );
    });

    test('stamps the library only once it is in place', () async {
      native('gleon_ref')
        ..createSync(recursive: true)
        ..writeAsStringSync('old\n');
      // The library cannot replace a directory: the build is interrupted.
      Directory(native(libFileName).path).createSync(recursive: true);

      await expectLater(install(), throwsA(isA<FileSystemException>()));
      expect(native('gleon_ref').existsSync(), isFalse);
    });

    test(
      'copies to dist only after the stamp (dist is no hook input)',
      () async {
        // The dist directory cannot be created, so the copy fails.
        final dist = File('${tempPath()}/dist')..createSync();

        await expectLater(install(dist: dist.path), throwsA(anything));
        expect(native(libFileName).existsSync(), isTrue);
        expect(native('gleon_ref').readAsStringSync(), '$commit\n');
      },
    );
  });

  group('checkoutState', () {
    final repo = Uri.directory('/work/gleon');

    test('reads the commit and whether the library inputs changed', () async {
      final clean = _Git();
      expect(await NativeBuild.checkoutState(repo, runProcess: clean.run), (
        commit: commit,
        isDirty: false,
      ));
      expect(clean.calls.lastOrNull, [
        'status',
        '--porcelain',
        '--untracked-files=all',
        '--',
        ...SourceBuild.inputPaths(repo),
      ]);

      final dirty = _Git(status: ' M gleon-ffi/src/lib.rs\n');
      expect(await NativeBuild.checkoutState(repo, runProcess: dirty.run), (
        commit: commit,
        isDirty: true,
      ));
    });

    test('is unknown when git cannot tell', () async {
      expect(
        await NativeBuild.checkoutState(
          repo,
          runProcess: _Git(exitCode: 128).run,
        ),
        isNull,
      );
      expect(
        await NativeBuild.checkoutState(
          repo,
          runProcess: _Git(isInstalled: false).run,
        ),
        isNull,
      );
    });
  });
}

/// A git stand-in: `rev-parse` prints [head], `status` prints [status],
/// both exit with [exitCode]; without [isInstalled], git is not found.
final class _Git {
  _Git({this.status = '', this.exitCode = 0, this.isInstalled = true});

  static const head = '18bc3075e002360815ae856d0a854cb6a62fa5a5\n';

  final String status;
  final int exitCode;
  final bool isInstalled;

  /// Arguments of every call.
  final calls = <List<String>>[];

  /// A [ProcessRunner].
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) {
    if (!isInstalled) throw ProcessException(executable, arguments);
    calls.add(arguments);
    final out = arguments.firstOrNull == 'rev-parse' ? head : status;

    return .value(ProcessResult(1, exitCode, out, _noOutput));
  }

  static const _noOutput = '';
}
