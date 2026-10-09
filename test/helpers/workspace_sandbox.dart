import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/golden_tolerance.dart';
import 'package:gleon/src/core/config/gleon_session.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/flutter/flutter_session.dart';
import 'package:gleon/src/flutter/gleon_matches_golden_file.dart';
import 'package:gleon/src/flutter/ignore_regions.dart';
import 'package:json_schema/json_schema.dart';

/// The package goldens, relative to the package root (`flutter test`'s
/// working directory).
const goldenSource = 'test/goldens';

/// The gleon commit `native/gleon_ref` pins.
// ignore: avoid-explicit-type-declaration, not obvious from the initializer.
final String gleonPin =
    NativeTarget.readPin(Directory.current.uri) ?? fail('no native/gleon_ref');

/// `case.v3.json` of the pinned commit ([gleonPin]) in a sibling gleon
/// checkout (`../gleon`, as in CI), or null without that checkout or commit.
/// Read from git, not the working tree: the checkout may be at another
/// commit.
// ignore: avoid-explicit-type-declaration, not obvious from the initializer.
final JsonSchema? caseSchema = _loadCaseSchema();

/// A temporary directory for one test with copies of the package goldens
/// `blob.png` and `swatch.png` under `test/goldens/` (and any
/// `extraGoldens`), with Flutter's
/// `LocalFileComparator` rooted at `test/`: a gleon workspace when given a
/// `.gleon/gleon.yaml`.
///
/// `flutter test` runs test files in parallel processes, and failure
/// artifacts are named after the golden (`failures/swatch_testImage.png`), so
/// tests sharing a directory would race on them. The sandbox also keeps the
/// repository clean: failures and `--update-goldens` writes land in a temp
/// directory that is deleted after the test.
final class WorkspaceSandbox {
  /// Creates the sandbox and installs its comparator for the running test;
  /// with a [yaml] config it is a workspace, else no golden in it has one.
  ///
  /// [extraGoldens] maps a path under `test/` to a package golden file name
  /// (`swatch.png`, `blob.png` or `caption.png`) to copy there.
  factory WorkspaceSandbox.create(
    String? yaml, {
    Map<String, String> extraGoldens = const {},
  }) {
    final root = Directory(
      Directory.systemTemp
          .createTempSync('gleon_ws_')
          .resolveSymbolicLinksSync(),
    );
    if (yaml != null) {
      Directory('${root.path}/.gleon').createSync();
      _writeConfig(root, yaml);
    }
    final goldens = {
      'goldens/blob.png': 'blob.png',
      'goldens/swatch.png': 'swatch.png',
      ...extraGoldens,
    };
    for (final MapEntry(key: target, value: name) in goldens.entries) {
      final file = File('${root.path}/test/$target')
        ..parent.createSync(recursive: true);
      File('$goldenSource/$name').copySync(file.path);
    }
    final sandbox = WorkspaceSandbox._(root, goldenFileComparator);
    _current = sandbox;
    addTearDown(() => _release(sandbox));
    goldenFileComparator = LocalFileComparator(
      root.uri.resolve('test/sandbox_test.dart'),
    );

    return sandbox;
  }

  /// A sandbox whose goldens (all three) have no workspace.
  factory WorkspaceSandbox.withoutWorkspace() =>
      .create(null, extraGoldens: const {'goldens/caption.png': 'caption.png'});

  const WorkspaceSandbox._(this.root, this._original);

  /// The sandbox (workspace) root.
  final Directory root;

  /// The comparator's basedir: goldens are resolved against it.
  Directory get dir => .new('${root.path}/test');

  /// Where Flutter-style failure images of the running test are written.
  Directory get failures => .new('${dir.path}/failures');

  final GoldenFileComparator _original;

  static WorkspaceSandbox? _current;

  /// The sandbox the running test created last (for `setUp` users).
  static WorkspaceSandbox get current =>
      _current ?? (throw StateError('no WorkspaceSandbox in this test'));

  /// Every file under `.gleon/runs/` (empty when nothing was recorded).
  List<File> get recordedFiles {
    final runs = Directory('${root.path}/.gleon/runs');

    return runs.existsSync()
        ? runs.listSync(recursive: true).whereType<File>().toList()
        : const [];
  }

  /// The images kept for the golden named [name] on this platform in the
  /// default artifacts directory (`<dir>/<platform>/<name>/`).
  Directory artifactsOf(String name) =>
      .new('${root.path}/.gleon/runs/latest/artifacts/$hostPlatform/$name');

  /// Whether the case report of the golden named [name] on this platform
  /// exists.
  bool hasCase(String name) => _caseFile(name).existsSync();

  /// The case report of the golden named [name] on this platform:
  /// `cases/<platform>/<name>.json`.
  File _caseFile(String name) =>
      .new('${root.path}/.gleon/runs/latest/cases/$hostPlatform/$name.json');

  /// A session with the given values of `GLEON_METRICS`,
  /// `GLEON_ARTIFACTS_DIR` and `GLEON_RUN_ID` (unset by default, whatever the
  /// environment of the test run); its goldens under [root] belong to this
  /// workspace.
  GleonSession session({
    String metrics = '',
    String artifactsDir = '',
    String runId = '',
  }) => _disposedWithTest(
    .new(
      integration: FlutterSession.integration,
      environment: GleonEnvironment(
        metrics: metrics,
        artifactsDir: artifactsDir,
        runId: runId,
      ),
    ),
  );

  /// A gleon matcher bound to [session], so the environment of the test run
  /// never leaks in.
  GleonMatchesGoldenFile matcher(
    String key, {
    GoldenTolerance? tolerance,
    List<Rect> ignoreRegions = const [],
    double? textTolerance,
    GleonSession? session,
  }) => .new(
    Uri.parse(key),
    null,
    tolerance: tolerance,
    masks: IgnoreRegions.toMasks(ignoreRegions),
    textTolerance: textTolerance,
    session: session ?? this.session(),
  );

  /// The bytes of the golden [key] (relative to `test/`): byte inputs of
  /// the golden itself are identical.
  Uint8List goldenBytes(String key) =>
      File('${root.path}/test/$key').readAsBytesSync();

  /// The case report named [name] on this platform, validated against the
  /// committed schema.
  Map<String, Object?> readCase(String name) {
    final file = _caseFile(name);
    expect(file.existsSync(), isTrue, reason: '${file.path} was not written');
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, Object?>) throw StateError('not an object');
    expectMatchesCaseSchema(json);

    return json;
  }

  /// Replaces `.gleon/gleon.yaml` with [yaml] (the engine reads it again).
  void writeConfig(String yaml) => _writeConfig(root, yaml);

  /// Restores the comparator [sandbox] replaced and deletes it.
  static void _release(WorkspaceSandbox sandbox) {
    _current = null;
    goldenFileComparator = sandbox._original;
    sandbox.root.deleteSync(recursive: true);
  }
}

/// The name gleon gives this platform: the directory of its own goldens, and
/// the `fallback_platform` naming it.
String get hostPlatform =>
    (NativeTarget.host ?? fail('tests run on a native target')).gleonPlatform;

/// A platform other than this one.
String get foreignPlatform =>
    hostPlatform == 'linux-x86_64' ? 'windows-x86_64' : 'linux-x86_64';

void _writeConfig(Directory root, String yaml) =>
    File('${root.path}/.gleon/gleon.yaml').writeAsStringSync(yaml);

/// A session without a workspace and the given `GLEON_METRICS` value (unset
/// by default, like the other variables).
GleonSession sessionWithoutWorkspace({String metrics = ''}) =>
    _disposedWithTest(
      .new(
        integration: FlutterSession.integration,
        hasWorkspaces: false,
        environment: GleonEnvironment(metrics: metrics),
      ),
    );

/// [session], released when the running test ends instead of at garbage
/// collection.
GleonSession _disposedWithTest(GleonSession session) {
  addTearDown(session.dispose);

  return session;
}

/// Validates [json] against [caseSchema] when a gleon checkout is present.
void expectMatchesCaseSchema(Map<String, Object?> json) {
  final schema = caseSchema;
  if (schema == null) return;
  final result = schema.validate(json, validateFormats: true);

  expect(result.isValid, isTrue, reason: '${result.errors}\n$json');
}

JsonSchema? _loadCaseSchema() {
  final ProcessResult shown;
  try {
    shown = Process.runSync('git', [
      '-C',
      '../gleon',
      'show',
      '$gleonPin:gleon-model/schema/case.v3.json',
    ]);
  } on ProcessException {
    return null;
  }

  return shown.exitCode == 0
      ? JsonSchema.create(shown.stdout.toString())
      : null;
}
