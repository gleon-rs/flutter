import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/golden_tolerance.dart';
import 'package:gleon/src/core/config/gleon_session.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/flutter/flutter_session.dart';
import 'package:gleon/src/flutter/gleon_file_comparator.dart';
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

/// `case.v4.json` of the pinned commit ([gleonPin]) in a sibling gleon
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
  /// (`swatch.png`, `blob.png` or `caption.png`) to copy there. With
  /// [installsGleonComparator] the comparator is a [GleonFileComparator]
  /// with the sandbox's session, like `test/flutter_test_config.dart` would
  /// install it (the environment of the test run never leaks in).
  factory WorkspaceSandbox.create(
    String? yaml, {
    Map<String, String> extraGoldens = const {},
    bool installsGleonComparator = false,
  }) {
    final root = Directory(
      Directory.systemTemp.createTempSync(_prefix).resolveSymbolicLinksSync(),
    );
    // Before anything that may throw, so the directory never outlives the test.
    addTearDown(() => root.deleteSync(recursive: true));
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
    // Tear-downs run in reverse: the comparator is back before the directory
    // goes.
    addTearDown(_restore(goldenFileComparator));
    final sandbox = WorkspaceSandbox._(root);
    final testFile = root.uri.resolve('test/sandbox_test.dart');
    goldenFileComparator = installsGleonComparator
        ? GleonFileComparator.withSession(testFile, sandbox.session())
        : LocalFileComparator(testFile);

    return sandbox;
  }

  /// A sandbox whose goldens (all three) have no workspace.
  factory WorkspaceSandbox.withoutWorkspace() =>
      .create(null, extraGoldens: const {'goldens/caption.png': 'caption.png'});

  const WorkspaceSandbox._(this.root);

  /// The sandbox whose comparator `goldenFileComparator` is: the last one the
  /// running test created (for `setUp` users). Read from Flutter's global,
  /// not kept apart, so it can never point at another test's sandbox.
  factory WorkspaceSandbox.current() => switch (goldenFileComparator) {
    // `<temp>/gleon_ws_…/test/` (a directory: its last segment is empty): the
    // sandbox's own directory, not any path that happens to contain the
    // prefix.
    LocalFileComparator(
      basedir: final basedir && Uri(pathSegments: [..., final name, 'test', _]),
    )
        when name.startsWith(_prefix) =>
      ._(Directory.fromUri(basedir).parent),
    final other => throw StateError(
      'no WorkspaceSandbox in this test (goldenFileComparator is a '
      '${other.runtimeType})',
    ),
  };

  /// The sandbox (workspace) root.
  final Directory root;

  static const _prefix = 'gleon_ws_';

  /// The comparator's basedir: goldens are resolved against it.
  Directory get dir => .new('${root.path}/test');

  /// Where Flutter-style failure images of the running test are written.
  Directory get failures => .new('${dir.path}/failures');

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

  /// A tear-down that puts [original] back as `goldenFileComparator`.
  static VoidCallback _restore(GoldenFileComparator original) =>
      () => goldenFileComparator = original;
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
  ProcessResult git(List<String> arguments) =>
      Process.runSync('git', ['-C', '../gleon', ...arguments]);
  final ProcessResult pinned;
  try {
    pinned = git(['cat-file', '-e', '$gleonPin^{commit}']);
  } on ProcessException {
    return null;
  }
  // No checkout, or one without the pinned commit: nothing to validate with.
  if (pinned.exitCode != 0) return null;
  final shown = git(['show', '$gleonPin:$_caseSchemaPath']);
  if (shown.exitCode != 0) {
    // Loud: a silent skip would hide every report from the schema.
    throw StateError(
      '$_caseSchemaPath is not in the pinned gleon $gleonPin: the schema '
      'version of the test helpers and bin/src/case_check.dart differs from '
      "the pin's",
    );
  }

  return JsonSchema.create(shown.stdout.toString());
}

/// The case schema the reports of this package's engine follow.
const _caseSchemaPath = 'gleon-model/schema/case.v4.json';
