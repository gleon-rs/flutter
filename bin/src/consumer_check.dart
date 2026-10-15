/// The checks of `bin/consumer_check.dart` on the consumer app, in order.
/// Only `dart:*`, `crypto` and this package may be imported here (see
/// `build_native.dart`).

// Failure texts of the engine use "≤".
// ignore_for_file: avoid-non-ascii-symbols
library;

import 'dart:convert';
import 'dart:io';

import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import 'check_failure.dart';
import 'consumer_app.dart';
import 'release_server.dart';

/// Whether [output] of `flutter test` mentions [phrase]: Flutter wraps long
/// lines, so any run of whitespace matches a space.
bool hasPhrase(String output, String phrase) =>
    RegExp(RegExp.escape(phrase).replaceAll(RegExp(r'\\? '), r'\s+'))
        .hasMatch(output);

/// The checks, in order, on the consumer [app].
final class ConsumerCheck {
  const ConsumerCheck({
    required this.app,
    required this.library,
    required this.package,
    required this.server,
    required this.target,
  });

  final Directory app;
  final File library;
  final Directory package;
  final ReleaseServer server;
  final NativeTarget target;

  /// 1. The hook downloads the library from the release, and
  /// `--update-goldens` stamps the golden without any config.
  Future<void> download() async {
    stdout.writeln('--- 1. the hook downloads the library from the release');
    await _flutter(['pub', 'get']);
    final recorded = await _flutter(['test', '--update-goldens']);
    check(
      'the hook fetched the checksum list and the library, and compared the '
      'gleon commit of the release with its pin (requests: '
      '${server.requests})',
      isMet: [
        ReleaseServer.checksumsFileName,
        target.assetName,
        ReleaseDownload.pinFileName,
      ].every(server.requests.contains),
    );
    final golden = File('${app.path}/test/$consumerGolden');
    check(
      'the golden was written by --update-goldens',
      isMet: golden.existsSync(),
    );
    check(
      'the golden names the platform it was recorded on (no config needed)',
      isMet: latin1
          .decode(golden.readAsBytesSync())
          .contains('gleon:platform\u0000'),
    );
    check(
      'no warning while recording:\n$recorded',
      isMet: !hasPhrase(recorded, 'gleon: golden'),
    );
  }

  /// 2. The golden passes quietly; a changed digit fails on this platform,
  /// on its text alone, with the tip about `.gleon/gleon.yaml`.
  Future<void> compare() async {
    stdout.writeln('--- 2. the golden passes, a changed digit fails here');
    final passed = await _flutter(['test']);
    check('a quiet pass:\n$passed', isMet: !hasPhrase(passed, 'gleon: golden'));
    writeNumber(app, '43');
    final failed = await _flutter(['test'], shouldFail: true);
    check(
      'only the text failed, under the tolerance of the recording platform:\n'
      '$failed',
      isMet:
          hasPhrase(failed, 'text up to') &&
          hasPhrase(failed, 'text ≤ 5.00% per tile'),
    );
    check(
      'the failure points at .gleon/gleon.yaml:\n$failed',
      isMet: hasPhrase(failed, 'Tip: tolerances per golden'),
    );
    writeNumber(app, '42');
  }

  /// 3. Offline, the hook reuses its verified cache: the release is gone, the
  /// proxies are dead, and a changed hook input (the package pubspec) makes
  /// the hooks runner run the hook again.
  Future<void> offline() async {
    stdout.writeln('--- 3. offline: the hook reuses its cache');
    await server.close();
    File('${package.path}/pubspec.yaml').writeAsStringSync(
      '\n# consumer_check: a changed hook input.\n',
      mode: .append,
    );
    final before = _hookRuns;
    await _flutter(['test'], environment: _offline);
    check(
      'the hook ran again offline (its output: ${_hookOutputs.join(', ')})',
      isMet: _hookRuns.isAfter(before),
    );
  }

  /// The outputs the hooks runner keeps of each run of this package's hook.
  List<File> get _hookOutputs {
    final runs = Directory('${app.path}/.dart_tool/hooks_runner/gleon');

    return runs.existsSync()
        ? [
            for (final run in runs.listSync().whereType<Directory>())
              File('${run.path}/output.json'),
          ].where((output) => output.existsSync()).toList()
        : const [];
  }

  /// When the hook of this package last ran.
  DateTime get _hookRuns {
    DateTime last = .fromMillisecondsSinceEpoch(0);
    for (final output in _hookOutputs) {
      final modified = output.lastModifiedSync();
      if (modified.isAfter(last)) last = modified;
    }

    return last;
  }

  /// 4. Bundled like the pub.dev archive (the library under `native/`, no
  /// pin), the library needs no download at all: the hook resolves it again
  /// without its caches.
  Future<void> bundled() async {
    stdout.writeln('--- 4. bundled: the pub.dev archive ships the library');
    final pin = File('${package.path}/$nativePin');
    if (pin.existsSync()) pin.deleteSync();
    final bundled = File(
      '${package.path}/native/${target.key}/${target.libFileName}',
    )..parent.createSync(recursive: true);
    library.copySync(bundled.path);
    final hooksRunner = Directory('${app.path}/.dart_tool/hooks_runner');
    if (hooksRunner.existsSync()) hooksRunner.deleteSync(recursive: true);
    await _flutter(['test'], environment: _offline);
  }

  /// Every proxy variable the hook honors, pointing nowhere; the loopback
  /// stays direct, since `flutter test` itself talks to its test shell over
  /// a local socket (and the release's address then refuses at once).
  static Map<String, String> get _offline => {
    for (final name in const [
      'HTTPS_PROXY',
      'HTTP_PROXY',
      'https_proxy',
      'http_proxy',
    ])
      name: deadProxy,
    for (final name in const ['NO_PROXY', 'no_proxy'])
      name: 'localhost,127.0.0.1,::1',
  };

  /// `PATH` without the directories that hold Rust ([pathWithoutRust]).
  static String get _pathWithoutRust => pathWithoutRust(
    Platform.environment['PATH'] ?? _noPath,
    separator: Platform.isWindows ? ';' : ':',
    holds: (dir, tool) =>
        File('$dir/$tool${Platform.isWindows ? '.exe' : _noPath}').existsSync(),
  );

  static const _noPath = '';

  /// The cargo builds of the hook: none, since it only ever downloads or
  /// takes the bundled library (a source build needs `gleon_repo`).
  List<Directory> get _sourceBuilds {
    final shared = Directory('${app.path}/.dart_tool/hooks_runner/shared');

    return shared.existsSync()
        ? shared
              .listSync(recursive: true)
              .whereType<Directory>()
              .where((dir) => nameOf(dir) == 'cargo')
              .toList()
        : const [];
  }

  /// Runs `flutter` with [arguments] in the app and returns its output;
  /// fails unless it exits as [shouldFail] says.
  Future<String> _flutter(
    List<String> arguments, {
    Map<String, String> environment = const {},
    bool shouldFail = false,
  }) async {
    final command = 'flutter ${arguments.join(' ')}';
    stdout.writeln('\$ $command');
    final result = await Process.run(
      'flutter',
      arguments,
      workingDirectory: app.path,
      environment: {...environment, 'PATH': _pathWithoutRust},
      runInShell: Platform.isWindows,
    );
    final output = '${result.stdout}\n${result.stderr}';
    final hasFailed = result.exitCode != 0;
    if (hasFailed != shouldFail) {
      throw CheckFailure(
        '$command exited with ${result.exitCode} '
        '(expected ${shouldFail ? 'a failure' : 'success'}):\n$output',
      );
    }
    // A dependency of the hook that is missing reads as modified during the
    // build: the runner logs this and runs the hook again on every build.
    check(
      'the hook declares only dependencies that exist:\n$output',
      isMet: !output.contains('Build must be rerun'),
    );
    check(
      'the hook never builds from source: ${_sourceBuilds.join(', ')}',
      isMet: _sourceBuilds.isEmpty,
    );

    return output;
  }
}
