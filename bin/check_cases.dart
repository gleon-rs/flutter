/// Checks the case reports of a run: that each golden was compared where the
/// example's `fallback_platform` says it should be (CI proof of
/// platform-aware goldens).
///
/// ```sh
/// dart bin/check_cases.dart <runs dir> (--fallback-platform <os-arch> | --own)
///   [--min-cases <n>] [--outcome <outcome>]... [--run-id <id>]
/// ```
///
/// `<runs dir>` is a copy of `.gleon/runs/latest` (with `cases/`). With
/// `--fallback-platform`, reports of that platform compared the shared golden
/// with text (no `golden.fallback`, the default text tolerance of the goldens'
/// platform), and reports of every other platform fell back to it with text
/// ignored. With `--own`, every report compared its platform's own golden,
/// with text. Expects unset text tolerances (the defaults), as the example has.
///
/// Only `dart:*` may be imported here (see `build_native.dart`).
library;

import 'dart:convert';
import 'dart:io';

const _usage = '''
Usage: dart bin/check_cases.dart <runs dir> (--fallback-platform <os-arch> | --own)
  [--min-cases <n>] [--outcome <outcome>]... [--run-id <id>]

  --fallback-platform  the platform of the shared goldens (e.g. macos-aarch64)
  --own                every golden was compared with its platform's own
  --min-cases <n>      at least this many reports (default 1)
  --outcome <name>     an allowed outcome; repeatable (default identical, match)
  --run-id <id>        every report has this run id
''';

void main(List<String> args) {
  final expected = _CheckCases.parse(args);
  final cases = Directory('${expected.runs}/cases');
  if (!cases.existsSync()) _fail('${cases.path} does not exist.');
  final files =
      cases
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final problems = <String>[];
  for (final file in files) {
    final found = expected.problemsOf(
      _Case.of(json.decode(file.readAsStringSync())),
    );
    problems.addAll([for (final problem in found) '${file.path}: $problem']);
    stdout.writeln('${found.isEmpty ? 'ok  ' : 'FAIL'} ${file.path}');
  }
  if (files.length < expected.minCases) {
    problems.add(
      '${files.length} case reports, expected at least ${expected.minCases}.',
    );
  }
  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }
  stdout.writeln('${files.length} case reports as expected.');
}

/// What the reports of a run must show.
final class _CheckCases {
  const _CheckCases({
    required this.fallbackPlatform,
    required this.minCases,
    required this.outcomes,
    required this.runs,
    required this.runId,
  });

  factory _CheckCases.parse(List<String> args) {
    final positional = <String>[];
    String? fallbackPlatform;
    String? runId;
    bool isOwn = false;
    int minCases = 1;
    final outcomes = <String>{};
    final rest = args.iterator;
    while (rest.moveNext()) {
      switch (rest.current) {
        case '--fallback-platform':
          fallbackPlatform = _value(rest);

        case '--own':
          isOwn = true;

        case '--min-cases':
          minCases =
              int.tryParse(_value(rest)) ??
              _fail('--min-cases needs a number.\n\n$_usage');

        case '--outcome':
          outcomes.add(_value(rest));

        case '--run-id':
          runId = _value(rest);

        case '-h' || '--help':
          stdout.write(_usage);
          exit(0);

        case final other when other.startsWith('-'):
          _fail('unexpected argument $other.\n\n$_usage');

        case final directory:
          positional.add(directory);
      }
    }
    final runs = positional.singleOrNull;
    if (runs == null || isOwn == (fallbackPlatform != null)) {
      _fail(
        'pass a runs directory and one of --fallback-platform or --own.\n\n'
        '$_usage',
      );
    }

    return _CheckCases(
      fallbackPlatform: fallbackPlatform,
      minCases: minCases,
      outcomes: outcomes.isEmpty ? const {'identical', 'match'} : outcomes,
      runs: runs,
      runId: runId,
    );
  }

  /// The platform of the shared goldens; null: every report compared its
  /// platform's own golden (`--own`).
  final String? fallbackPlatform;

  /// The fewest reports.
  final int minCases;

  /// The allowed outcomes.
  final Set<String> outcomes;

  /// The runs directory (with `cases/`).
  final String runs;

  /// The run id of every report, if given.
  final String? runId;

  /// The default text tolerance on the goldens' own platform.
  static const _ownPlatformText = 0.05;

  /// The default text tolerance against another platform's golden.
  static const _fallbackText = 1.0;

  /// What [report] shows that it should not.
  List<String> problemsOf(_Case report) {
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

  /// A report of another platform: its own golden, or (unless `--own`) the
  /// shared golden in its place, with text ignored.
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

  factory _Case.of(Object? report) => switch (report) {
    {
      'comparison': final Map<String, Object?> comparison,
      'golden':
          {'path': final String path} && final Map<String, Object?> golden,
      'outcome': final String outcome,
      'platform': {'arch': final String arch, 'os': final String os},
      'schema_version': final int version,
    } =>
      _Case(
        fallback: golden['fallback']?.toString(),
        outcome: outcome,
        path: path,
        platform: '$os-$arch',
        runId: report['run_id']?.toString(),
        text: _share(comparison['text_tolerance']),
        version: version,
      ),
    _ => _fail('not a case report: ${json.encode(report)}'),
  };

  static double? _share(Object? value) =>
      value is num ? value.toDouble() : null;

  /// The shared golden compared in place of [path], if any.
  final String? fallback;

  /// How the comparison ended.
  final String outcome;

  /// The golden of this platform (`/`-separated).
  final String path;

  /// `<os>-<arch>` of the recording platform.
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
}

/// The value following the flag that [rest] is at.
String _value(Iterator<String> rest) {
  final flag = rest.current;

  return rest.moveNext()
      // ignore: use-existing-variable, `moveNext` advanced to the value.
      ? rest.current
      : _fail('$flag needs a value.\n\n$_usage');
}

Never _fail(String message) {
  stderr.writeln('check_cases: $message');
  exit(64);
}
