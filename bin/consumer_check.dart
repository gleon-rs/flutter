/// Checks the package the way a consumer meets it: a fresh Flutter app with
/// gleon as a dependency without `native/` (a git or pub.dev dependency with
/// no prebuilt library) and no Rust on `PATH`, whose build hook downloads the
/// library of this host from a local release (checksums and all), reuses it
/// offline, and then finds it bundled as in the pub.dev archive. The app has
/// no `.gleon/gleon.yaml`: `--update-goldens` stamps its golden, a changed
/// digit fails on this platform, and a stray `~/.gleon/gleon.yaml` (CI only)
/// changes nothing.
///
/// ```sh
/// dart bin/consumer_check.dart [--target <key>] [--work-dir <dir>] [--keep]
///   [--stray-home-config]
/// ```
///
/// Needs `native/<target>/<library>` (`dart bin/build_native.dart`, or the
/// setup action of CI): it is what the local release serves.
///
/// Only `dart:*`, this package and `src/` may be imported here (see
/// `build_native.dart`).
library;

import 'dart:io';

import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import 'src/check_failure.dart';
import 'src/cli.dart';
import 'src/consumer_app.dart';
import 'src/consumer_check.dart';
import 'src/release_server.dart';
import 'src/run_resources.dart';
import 'src/stray_home_config.dart';

const _cli = Cli('consumer_check', '''
Usage: dart bin/consumer_check.dart [--target <key>] [--work-dir <dir>]
  [--keep] [--stray-home-config]

  --target <key>        the native target of this host (default: the host)
  --work-dir <dir>      where the temporary directory of the consumer app and
                        the package copy goes, outside the package (default:
                        the system's)
  --keep                leave the work directory behind
  --stray-home-config   write an invalid ~/.gleon/gleon.yaml for the run (CI
                        only: it must not apply to a project without .git)
''');

Future<void> main(List<String> args) async {
  final (:hasStrayHomeConfig, :isKept, :target, :workDir) = _parse(args);
  final packageRoot = await _cli.packageRoot();
  final library = File.fromUri(
    packageRoot.resolve('native/${target.key}/${target.libFileName}'),
  );
  if (!library.existsSync()) {
    _cli.fail(
      '${library.path} is missing: build it with `dart bin/build_native.dart`.',
    );
  }
  final parent = (workDir ?? .systemTemp).absolute;
  if (isWithin(parent, Directory.fromUri(packageRoot))) {
    _cli.failUsage('--work-dir must lie outside the package (it is copied).');
  }
  // Always a fresh directory, also inside `--work-dir`: the only one deleted.
  final work = parent.createTempSync('gleon_consumer_');
  stdout.writeln('consumer_check: working in ${work.path}');
  final resources = RunResources(work, isKept: isKept);
  // Ctrl+C and a cancelled CI job skip `finally`: the same cleanup then.
  final interrupts = [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ].map((signal) => signal.watch().listen(resources.interrupt)).toList();
  try {
    final package = Directory('${work.path}/package');
    copyPackage(Directory.fromUri(packageRoot), package);
    final server = await _release(packageRoot, target, library);
    resources
      ..server = server
      ..stray = hasStrayHomeConfig ? _strayHomeConfig() : null;
    await _check(
      ConsumerCheck(
        app: Directory('${work.path}/app'),
        library: library,
        package: package,
        server: server,
        target: target,
      ),
    );
  } on CheckFailure catch (error) {
    // Not `fail`: exiting here would skip the cleanup below.
    _cli.report(error.message);
  } finally {
    for (final interrupt in interrupts) {
      await interrupt.cancel();
    }
    await resources.cleanUp();
  }
}

/// The local release of [library] of [target]: like a GitHub Release, with
/// the gleon commit it was built from (the pin of the package at
/// [packageRoot]), which the hook compares with the pin of the package copy.
Future<ReleaseServer> _release(
  Uri packageRoot,
  NativeTarget target,
  File library,
) {
  final pin = File.fromUri(packageRoot.resolve(nativePin));

  return ReleaseServer.start({
    target.assetName: library,
    if (pin.existsSync()) ReleaseDownload.pinFileName: pin,
  });
}

/// Runs the checks of [consumer] in order.
Future<void> _check(ConsumerCheck consumer) async {
  writeConsumerApp(
    consumer.app,
    package: consumer.package,
    releaseUrl: consumer.server.url,
  );
  await consumer.download();
  await consumer.compare();
  await consumer.offline();
  await consumer.bundled();
  stdout.writeln('consumer_check: all checks passed.');
}

({
  bool hasStrayHomeConfig,
  bool isKept,
  NativeTarget target,
  Directory? workDir,
})
_parse(List<String> args) {
  NativeTarget? target;
  Directory? workDir;
  bool isKept = false;
  bool hasStrayHomeConfig = false;
  final rest = args.iterator;
  while (rest.moveNext()) {
    switch (rest.current) {
      case '--target':
        final key = _cli.value(rest);
        target =
            NativeTarget.byKey(key) ??
            _cli.failUsage(
              'unknown target $key (expected ${NativeTarget.keys}).',
            );

      case '--work-dir':
        workDir = Directory(_cli.value(rest))..createSync(recursive: true);

      case '--keep':
        isKept = true;

      case '--stray-home-config':
        hasStrayHomeConfig = true;

      case '-h' || '--help':
        _cli.help();

      case final other:
        _cli.failUsage('unexpected argument $other.');
    }
  }

  return (
    hasStrayHomeConfig: hasStrayHomeConfig,
    isKept: isKept,
    target:
        target ??
        NativeTarget.host ??
        _cli.fail('this host is not a supported target; pass --target.'),
    workDir: workDir,
  );
}

/// An invalid `~/.gleon/gleon.yaml` for this run (CI only).
StrayHomeConfig _strayHomeConfig() {
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      (throw const CheckFailure(
        '--stray-home-config needs HOME or USERPROFILE.',
      ));
  final stray = StrayHomeConfig.write(home);
  stdout.writeln('consumer_check: wrote a stray ${stray.file.path}');

  return stray;
}
