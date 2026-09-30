import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/compare/golden_tolerance.dart';
import 'package:gleon/src/core/config/gleon_session.dart';
import 'package:gleon/src/flutter/flutter_session.dart';
import 'package:gleon/src/flutter/gleon_matches_golden_file.dart';
import 'package:gleon/src/flutter/ignore_regions.dart';
import 'package:json_schema/json_schema.dart';

import 'golden_sandbox.dart';

/// `case.v1.json` of a sibling gleon checkout (as in CI), or null.
// ignore: avoid-explicit-type-declaration, not obvious from the initializer.
final JsonSchema? caseSchema = _loadCaseSchema();

/// A temporary gleon workspace for one test: `.gleon/gleon.yaml` plus copies
/// of the package goldens under `test/goldens/` (and any `extraGoldens`),
/// with Flutter's `LocalFileComparator` rooted at `test/`.
final class WorkspaceSandbox {
  /// Creates the workspace and installs its comparator for the running test.
  ///
  /// [extraGoldens] maps a path under `test/` to a package golden file name
  /// (`swatch.png` or `blob.png`) to copy there.
  factory WorkspaceSandbox.create(
    String yaml, {
    Map<String, String> extraGoldens = const {},
  }) {
    final root = Directory(
      Directory.systemTemp
          .createTempSync('gleon_ws_')
          .resolveSymbolicLinksSync(),
    );
    Directory('${root.path}/.gleon').createSync();
    File('${root.path}/.gleon/gleon.yaml').writeAsStringSync(yaml);
    const source = GoldenSandbox.source;
    final goldens = {
      'goldens/blob.png': 'blob.png',
      'goldens/swatch.png': 'swatch.png',
      ...extraGoldens,
    };
    for (final MapEntry(key: target, value: name) in goldens.entries) {
      final file = File('${root.path}/test/$target')
        ..parent.createSync(recursive: true);
      File('$source/$name').copySync(file.path);
    }
    final sandbox = WorkspaceSandbox._(root, goldenFileComparator);
    addTearDown(sandbox._dispose);
    goldenFileComparator = LocalFileComparator(
      root.uri.resolve('test/sandbox_test.dart'),
    );

    return sandbox;
  }

  const WorkspaceSandbox._(this.root, this._original);

  /// The workspace root.
  final Directory root;

  final GoldenFileComparator _original;

  /// Every file under `.gleon/runs/` (empty when nothing was recorded).
  List<File> get recordedFiles {
    final runs = Directory('${root.path}/.gleon/runs');

    return runs.existsSync()
        ? runs.listSync(recursive: true).whereType<File>().toList()
        : const [];
  }

  /// A session with the given `GLEON_METRICS` value (unset by default,
  /// whatever the environment of the test run); its goldens under [root]
  /// belong to this workspace.
  // ignore: prefer-static-method, reads as this workspace's session in tests.
  GleonSession session({String metricsEnv = GleonSession.unsetMetricsEnv}) =>
      .new(integration: FlutterSession.integration, metricsEnv: metricsEnv);

  /// A gleon matcher bound to [session], so the environment of the test run
  /// never leaks in.
  GleonMatchesGoldenFile matcher(
    String key, {
    GoldenTolerance? tolerance,
    List<Rect> ignoreRegions = const [],
    GleonSession? session,
  }) => .new(
    Uri.parse(key),
    null,
    tolerance: tolerance,
    masks: IgnoreRegions.toMasks(ignoreRegions),
    session: session ?? this.session(),
  );

  /// The case report named [name], validated against the committed schema.
  Map<String, Object?> readCase(String name) {
    final file = File('${root.path}/.gleon/runs/latest/cases/$name.json');
    expect(file.existsSync(), isTrue, reason: '${file.path} was not written');
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, Object?>) throw StateError('not an object');
    expectMatchesCaseSchema(json);

    return json;
  }

  void _dispose() {
    goldenFileComparator = _original;
    root.deleteSync(recursive: true);
  }
}

/// A session without a workspace and the given `GLEON_METRICS` value (unset
/// by default).
GleonSession sessionWithoutWorkspace({
  String metricsEnv = GleonSession.unsetMetricsEnv,
}) => .new(
  integration: FlutterSession.integration,
  hasWorkspaces: false,
  metricsEnv: metricsEnv,
);

/// Validates [json] against [caseSchema] when a gleon checkout is present.
void expectMatchesCaseSchema(Map<String, Object?> json) {
  final schema = caseSchema;
  if (schema == null) return;
  final result = schema.validate(json, validateFormats: true);

  expect(result.isValid, isTrue, reason: '${result.errors}\n$json');
}

JsonSchema? _loadCaseSchema() {
  final file = File('../gleon/gleon-model/schema/case.v1.json');

  return file.existsSync() ? JsonSchema.create(file.readAsStringSync()) : null;
}
