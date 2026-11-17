import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/source_build.dart';

import '../../bin/src/native_build.dart';
import '../../bin/src/native_target_builds.dart';

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

    Future<({List<File> copies, crypto.Digest sha256})> install({
      String? dist,
    }) => NativeBuild.install(
      built(),
      target,
      packageRoot: Directory('${tempPath()}/package').uri,
      builtFrom: commit,
      dist: dist,
    );

    test('writes the library, its stamp and the release asset', () async {
      final (:copies, :sha256) = await install(dist: '${tempPath()}/dist');

      expect(native(libFileName).readAsStringSync(), 'library');
      expect(native('gleon_ref').readAsStringSync(), '$commit\n');
      expect(
        File('${tempPath()}/dist/$assetName').readAsStringSync(),
        'library',
      );
      expect(
        [for (final file in copies) file.uri.pathSegments.lastOrNull],
        [libFileName, assetName],
      );
      expect(sha256, crypto.sha256.convert(utf8.encode('library')));
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

  group('build_native targets', () {
    List<String> keys(
      List<String> requested, {
      required String hostOs,
      required NativeTarget? host,
    }) => [
      for (final resolved in NativeTargetBuilds.resolveKeys(
        requested,
        hostOs: hostOs,
        host: host,
      ))
        resolved.key,
    ];

    Map<String, List<String>?> subcommands(String hostOs, NativeTarget host) =>
        {
          for (final each in NativeTarget.values)
            each.key: each.cargoSubcommand(hostOs: hostOs, host: host),
        };

    test('macOS builds everything, Linux and Windows through wrappers', () {
      expect(subcommands('macos', .macosArm64), {
        'linux-arm64': ['zigbuild'],
        'linux-x64': ['zigbuild'],
        'macos-arm64': ['build'],
        'windows-x64': ['xwin', 'build'],
      });
      expect(keys(['all'], hostOs: 'macos', host: .macosArm64), [
        'linux-arm64',
        'linux-x64',
        'macos-arm64',
        'windows-x64',
      ]);
    });

    test('Linux builds the other architecture with zigbuild', () {
      expect(subcommands('linux', .linuxX64), {
        'linux-arm64': ['zigbuild'],
        'linux-x64': ['build'],
        'macos-arm64': null,
        'windows-x64': ['xwin', 'build'],
      });
      expect(subcommands('linux', .linuxArm64)['linux-arm64'], ['build']);
      expect(keys(['all'], hostOs: 'linux', host: .linuxArm64), [
        'linux-arm64',
        'linux-x64',
        'windows-x64',
      ]);
    });

    test('Windows builds itself with cargo and Linux with zigbuild', () {
      expect(subcommands('windows', .windowsX64), {
        'linux-arm64': ['zigbuild'],
        'linux-x64': ['zigbuild'],
        'macos-arm64': null,
        'windows-x64': ['build'],
      });
    });

    test('keys keep their order once each', () {
      expect(
        keys(['host', 'linux-arm64', 'all'], hostOs: 'linux', host: .linuxX64),
        ['linux-x64', 'linux-arm64', 'windows-x64'],
      );
    });

    test('every target is checked before anything is built', () {
      Matcher throwsFormat(String message) => throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains(message),
        ),
      );
      expect(
        () => keys(
          ['linux-x64', 'macos-arm64'],
          hostOs: 'linux',
          host: .linuxX64,
        ),
        throwsFormat('macos-arm64 can only be built on macos'),
      );
      expect(
        () => keys(['host'], hostOs: 'macos', host: null),
        throwsFormat('this host is not a supported target'),
      );
      expect(
        () => keys(['macos-x64'], hostOs: 'macos', host: .macosArm64),
        throwsFormat('unknown target macos-x64'),
      );
    });
  });
}

/// A git stand-in: `rev-parse` prints [head], `status` prints [status],
/// both exit with [exitCode]; without [isInstalled], git is not found.
final class _Git {
  new({this.status = '', this.exitCode = 0, this.isInstalled = true});

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

    return .syncValue(ProcessResult(1, exitCode, out, _noOutput));
  }

  static const _noOutput = '';
}
