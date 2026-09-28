import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../compare/golden_tolerance.dart';
import '../compare/mask_zone.dart';
import '../config/gleon_workspace.dart';
import '../io/atomic_write.dart';
import '../native/native_metrics.dart';
import 'case_outcome.dart';
import 'case_source.dart';
import 'png_info.dart';

/// One golden comparison, serialized to the `gleon-model` case report
/// (`case.v1.json` in the gleon repository) at
/// `.gleon/runs/latest/cases/<name>.json`.
@immutable
final class CaseReport {
  /// Creates a report.
  const CaseReport({
    required this.name,
    required this.goldenPath,
    required this.golden,
    required this.candidate,
    required this.source,
    required this.platform,
    required this.tolerance,
    required this.masks,
    required this.policyVersion,
    required this.outcome,
    required this.totalMilliseconds,
    required this.recordedAt,
    this.testName,
    this.message,
    this.metrics,
    this.nativeMilliseconds,
  });

  /// Version of the case report format.
  static const schemaVersion = 1;

  /// Lines of `.gleon/.gitignore`, identical to what `gleon init` writes.
  static const gitignoreLines = [
    'blobs/',
    'runs/',
    '.env',
    '.env.local',
    'credentials',
    'dashboard.html',
    'history.json',
  ];

  /// Canonical gleon test name (also the file name).
  final String name;

  /// Golden path relative to the workspace root, `/`-separated.
  final String goldenPath;

  /// The committed golden.
  final PngInfo golden;

  /// The image of this run.
  final PngInfo candidate;

  /// What produced the candidate.
  final CaseSource source;

  /// Host platform (`{"os": ..., "arch": ...}`).
  final Map<String, Object?> platform;

  /// The effective tolerance.
  final GoldenTolerance tolerance;

  /// The effective masks.
  final List<MaskZone> masks;

  /// Version of the engine's tolerant decision policy.
  final int policyVersion;

  /// Result of the comparison.
  final CaseOutcome outcome;

  /// The whole comparison in milliseconds.
  final double totalMilliseconds;

  /// When the case was recorded.
  final DateTime recordedAt;

  /// The producing test, when known.
  final String? testName;

  /// Failure reason or error.
  final String? message;

  /// Whole-image metrics, when a pixel comparison ran.
  final NativeMetrics? metrics;

  /// Time spent in the native engine, when it ran.
  final double? nativeMilliseconds;

  /// The report as JSON.
  Map<String, Object> toJson() {
    final metricsJson = metrics?.toJson();

    return {
      'candidate': candidate.toJson(),
      'comparison': {
        'masks': [for (final mask in masks) mask.toNativeJson()],
        'policy_version': policyVersion,
        'tolerance': tolerance.toNativeJson(),
      },
      'golden': {'path': goldenPath, ...golden.toJson()},
      'message': ?message,
      'metrics': ?metricsJson,
      'name': name,
      'outcome': outcome.json,
      'platform': platform,
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'regions': [
        if (metricsJson != null) {'kind': 'image', 'metrics': metricsJson},
      ],
      'schema_version': schemaVersion,
      'source': source.toJson(),
      if (testName case final test?) 'test': {'name': test},
      'timings_ms': {'native': ?nativeMilliseconds, 'total': totalMilliseconds},
    };
  }

  /// Writes the report atomically into [workspace] and returns the file.
  ///
  /// Creates `.gleon/.gitignore` (with the `gleon init` content, which ignores
  /// `runs/`) when it is missing; an existing one is left alone.
  Future<File> write(GleonWorkspace workspace) async {
    final gitignore = File('${workspace.gleonDir.path}/.gitignore');
    if (!gitignore.existsSync()) {
      await AtomicWrite.bytes(
        gitignore,
        utf8.encode('${gitignoreLines.join('\n')}\n'),
      );
    }
    final file = File('${workspace.casesDir.path}/$name.json');
    await AtomicWrite.bytes(
      file,
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(toJson())}\n'),
    );

    return file;
  }
}
