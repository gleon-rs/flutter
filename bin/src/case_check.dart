import 'dart:convert';

/// What the case reports of a run must show: that each golden was compared
/// where the workspace's `fallback_platform` says it should be (the CI proof
/// of platform-aware goldens, `bin/check_cases.dart`).
///
/// With a [fallbackPlatform], reports of that platform compared the shared
/// golden with text (no `golden.fallback`, the default text tolerance of the
/// goldens' platform), and reports of every other platform fell back to it
/// with text ignored. Without, every report compared its platform's own
/// golden, with text. Expects unset text tolerances (the defaults).
///
/// Plain Dart (no Flutter imports): maintainer tooling, tested directly.
final class CaseCheck {
  /// Checks reports against [fallbackPlatform] (null: own goldens only).
  const CaseCheck({
    required this.fallbackPlatform,
    this.minCases = 1,
    this.outcomes = defaultOutcomes,
    this.runId,
  });

  /// The platform key of the shared goldens (e.g. `macos-aarch64`); null:
  /// every report compared its platform's own golden.
  final String? fallbackPlatform;

  /// The fewest reports.
  final int minCases;

  /// The allowed outcomes.
  final Set<String> outcomes;

  /// The run id of every report, if given.
  final String? runId;

  /// The outcomes allowed unless others are given: passes.
  static const defaultOutcomes = {'identical', 'match'};

  /// The default text tolerance on the goldens' own platform.
  static const _ownPlatformText = 0.05;

  /// The default text tolerance against another platform's golden.
  static const _fallbackText = 1.0;

  /// The key gleon gives a platform, which names the directory of its own
  /// goldens: `<os>-<arch>`, or `os=<os>+arch=<arch>` when either contains
  /// `-`, so no two platforms share one (`PlatformInfo::to_key` in
  /// gleon-model's `src/platform.rs`).
  static String platformKey({required String os, required String arch}) =>
      os.contains('-') || arch.contains('-')
      ? 'os=$os+arch=$arch'
      : '$os-$arch';

  /// What the report [content] (JSON text of one case report file) shows
  /// that it should not; empty: as expected.
  List<String> problemsOfReport(String content) {
    final Object? decoded;
    try {
      decoded = json.decode(content);
    } on FormatException catch (error) {
      return ['invalid JSON (${error.message})'];
    }
    final report = _Case.of(decoded);
    if (report == null) return const ['not a case report'];
    final _Case(:outcome, :platform, runId: recorded, :version) = report;

    return [
      if (version != 2) 'schema_version $version, expected 2',
      if (!outcomes.contains(outcome))
        'outcome $outcome, expected one of ${outcomes.join(', ')}',
      if (runId case final expected? when recorded != expected)
        'run_id ${recorded ?? 'none'}, expected $expected',
      ...platform == fallbackPlatform
          ? _sharedProblemsOf(report)
          : _ownProblemsOf(report),
    ];
  }

  /// The problem of a run with [count] reports, if it has too few.
  String? tooFew(int count) => count < minCases
      ? '$count case reports, expected at least $minCases.'
      : null;

  /// A report of the goldens' platform: it compared the shared golden, with
  /// text.
  static List<String> _sharedProblemsOf(_Case report) {
    final _Case(:fallback, :path, :text) = report;

    return [
      if (fallback != null) 'compared $fallback, expected $path itself',
      if (text != _ownPlatformText)
        'text tolerance ${text ?? 'none'}, expected $_ownPlatformText',
    ];
  }

  /// A report of another platform: its own golden, or (with a
  /// [fallbackPlatform]) the shared golden in its place, with text ignored.
  List<String> _ownProblemsOf(_Case report) {
    final _Case(:directory, :fallback, :path, :platform, :sharedPath, :text) =
        report;
    final isFallback = fallbackPlatform != null;
    final expectedText = isFallback ? _fallbackText : _ownPlatformText;

    return [
      if (directory != platform)
        'golden.path $path is not in a $platform/ directory',
      if (isFallback && fallback != sharedPath)
        'compared ${fallback ?? 'its own golden'}, expected $sharedPath',
      if (!isFallback && fallback != null) 'compared $fallback, expected $path',
      if (text != expectedText)
        'text tolerance ${text ?? 'none'}, expected $expectedText',
    ];
  }
}

/// The fields of a case report that are checked.
final class _Case {
  const _Case({
    required this.fallback,
    required this.outcome,
    required this.path,
    required this.platform,
    required this.runId,
    required this.text,
    required this.version,
  });

  /// The checked fields of [report], or null when it is no case report.
  static _Case? of(Object? report) => switch (report) {
    {
      'comparison': final Map<String, Object?> comparison,
      'golden':
          {'path': final String path} && final Map<String, Object?> golden,
      'outcome': final String outcome,
      'platform': {'arch': final String arch, 'os': final String os},
      'schema_version': final int version,
    } =>
      .new(
        fallback: golden['fallback']?.toString(),
        outcome: outcome,
        path: path,
        platform: CaseCheck.platformKey(os: os, arch: arch),
        runId: report['run_id']?.toString(),
        text: _share(comparison['text_tolerance']),
        version: version,
      ),
    _ => null,
  };

  /// The shared golden compared in place of [path], if any.
  final String? fallback;

  /// How the comparison ended.
  final String outcome;

  /// The golden of this platform (`/`-separated).
  final String path;

  /// The key of the recording platform ([CaseCheck.platformKey]).
  final String platform;

  /// The run that recorded it.
  final String? runId;

  /// The text tolerance it was compared with.
  final double? text;

  /// The case report schema version.
  final int version;

  /// The directory of [path], where a platform's own goldens are.
  String? get directory => path.split('/').reversed.skip(1).firstOrNull;

  /// [path] without its platform directory: the shared golden.
  String get sharedPath {
    final segments = path.split('/');
    final directories = segments.length > 1 ? segments.length - 2 : 0;

    return [...segments.take(directories), ?segments.lastOrNull].join('/');
  }

  static double? _share(Object? value) =>
      value is num ? value.toDouble() : null;
}
