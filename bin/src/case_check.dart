import 'dart:convert';

/// What the case reports of a run must show: that each golden was compared
/// the way the workspace's `fallback_platform` says (the CI proof of
/// platform-aware goldens, `bin/check_cases.dart`).
///
/// Every golden was recorded on [fallbackPlatform] (its `golden.platform`
/// names it, or no other platform: no golden of another platform crept in).
/// Reports of [fallbackPlatform] compared it with text (the default text
/// tolerance of the platform a golden was recorded on), reports of every
/// other platform with text ignored. Expects unset text tolerances (the
/// defaults).
///
/// Plain Dart (no Flutter imports): maintainer tooling, tested directly.
final class CaseCheck {
  /// Checks reports against [fallbackPlatform].
  const CaseCheck({
    required this.fallbackPlatform,
    this.minCases = 1,
    this.outcomes = defaultOutcomes,
    this.runId,
  });

  /// The platform key of the canonical platform (e.g. `macos-aarch64`).
  final String fallbackPlatform;

  /// The fewest reports.
  final int minCases;

  /// The allowed outcomes.
  final Set<String> outcomes;

  /// The run id of every report, if given.
  final String? runId;

  /// The outcomes allowed unless others are given: passes.
  static const defaultOutcomes = {'identical', 'match'};

  /// The default text tolerance on the platform a golden was recorded on.
  static const _ownText = 0.05;

  /// The default text tolerance on any other platform.
  static const _otherText = 1.0;

  /// The key gleon gives a platform, which names the directory of its case
  /// reports: `<os>-<arch>`, or `os=<os>+arch=<arch>` when either contains
  /// `-`, so no two platforms share one (`PlatformInfo::to_key` in
  /// gleon-model's `src/platform.rs`).
  static String platformKey({required String os, required String arch}) =>
      os.contains('-') || arch.contains('-')
      ? 'os=$os+arch=$arch'
      : '$os-$arch';

  /// The case report schema version gleon writes.
  static const _schemaVersion = 5;

  /// What the report [content] (JSON text of one case report file at
  /// [location], `/`-separated and relative to `cases/`) shows that it
  /// should not; empty: as expected. A report lies at
  /// `<platform key>/<name>.json`, like the gleon CLI reads it.
  List<String> problemsOfReport(String content, {required String location}) {
    final Object? decoded;
    try {
      decoded = json.decode(content);
    } on FormatException catch (error) {
      return ['invalid JSON (${error.message})'];
    }
    final report = _Case.of(decoded);
    if (report == null) return const ['not a case report'];
    final _Case(
      :name,
      :outcome,
      :platform,
      :recorded,
      runId: reportRunId,
      :text,
      :version,
    ) = report;
    final belongs = '$platform/$name.json';
    final expectedText = platform == fallbackPlatform ? _ownText : _otherText;

    return [
      if (location != belongs) 'lies at $location, expected $belongs',
      if (version != _schemaVersion)
        'schema_version $version, expected $_schemaVersion',
      if (!outcomes.contains(outcome))
        'outcome $outcome, expected one of ${outcomes.join(', ')}',
      if (runId case final expected? when reportRunId != expected)
        'run_id ${reportRunId ?? 'none'}, expected $expected',
      if (recorded case final origin? when origin != fallbackPlatform)
        'golden recorded on $origin, expected $fallbackPlatform',
      if (text != expectedText)
        'text tolerance ${text ?? 'none'}, expected $expectedText',
    ];
  }

  /// The problem of a run with [count] reports, if it has too few.
  String? tooFew(int count) => count < minCases
      ? '$count case reports, expected at least $minCases.'
      : null;
}

/// The fields of a case report that are checked.
final class _Case {
  const _Case({
    required this.recorded,
    required this.name,
    required this.outcome,
    required this.platform,
    required this.runId,
    required this.text,
    required this.version,
  });

  /// The checked fields of [report], or null when it is no case report.
  static _Case? of(Object? report) => switch (report) {
    {
      'comparison': final Map<String, Object?> comparison,
      'golden': final Map<String, Object?> golden,
      'name': final String name,
      'outcome': final String outcome,
      'platform': {'arch': final String arch, 'os': final String os},
      'schema_version': final int version,
    } =>
      .new(
        recorded: golden['platform']?.toString(),
        name: name,
        outcome: outcome,
        platform: CaseCheck.platformKey(os: os, arch: arch),
        runId: report['run_id']?.toString(),
        text: _share(comparison['text_tolerance']),
        version: version,
      ),
    _ => null,
  };

  /// The platform the golden was recorded on (its stamp), if it has one.
  final String? recorded;

  /// The canonical name of the golden, the same on every platform.
  final String name;

  /// How the comparison ended.
  final String outcome;

  /// The key of the recording platform ([CaseCheck.platformKey]).
  final String platform;

  /// The run that recorded it.
  final String? runId;

  /// The text tolerance it was compared with.
  final double? text;

  /// The case report schema version.
  final int version;

  static double? _share(Object? value) =>
      value is num ? value.toDouble() : null;
}
