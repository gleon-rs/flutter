/// Checks the case reports of a run: that each golden was compared where the
/// example's `fallback_platform` says it should be (CI proof of
/// platform-aware goldens; the rules are `CaseCheck` in
/// `lib/src/core/tooling/case_check.dart`).
///
/// ```sh
/// dart bin/check_cases.dart <runs dir> (--fallback-platform <key> | --own)
///   [--min-cases <n>] [--outcome <outcome>]... [--run-id <id>]
/// ```
///
/// `<runs dir>` is a copy of `.gleon/runs/latest` (with `cases/`). A file
/// that is no case report (invalid JSON, another value) is a problem of the
/// run, not a crash: every file is checked, then the run fails.
///
/// Only `dart:*` and this package may be imported here (see
/// `build_native.dart`).
library;

import 'dart:io';

import 'src/case_check.dart';
import 'src/cli.dart';

const _cli = Cli('check_cases', '''
Usage: dart bin/check_cases.dart <runs dir> (--fallback-platform <key> | --own)
  [--min-cases <n>] [--outcome <outcome>]... [--run-id <id>]

  --fallback-platform  the platform key of the shared goldens (e.g.
                       macos-aarch64)
  --own                every golden was compared with its platform's own
  --min-cases <n>      at least this many reports (default 1)
  --outcome <name>     an allowed outcome; repeatable (default identical, match)
  --run-id <id>        every report has this run id
''');

void main(List<String> args) {
  final (:check, :runs) = _parse(args);
  final cases = Directory('$runs/cases');
  if (!cases.existsSync()) _cli.fail('${cases.path} does not exist.');
  final files =
      cases
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  // Locations relative to `cases/`, `/`-separated on every OS: the segments
  // of the file's URI below the directory's (whose URI ends in `/`).
  final depth = cases.absolute.uri.pathSegments.length - 1;
  final problems = <String>[];
  for (final file in files) {
    final found = check.problemsOfReport(
      file.readAsStringSync(),
      location: file.absolute.uri.pathSegments.skip(depth).join('/'),
    );
    problems.addAll([for (final problem in found) '${file.path}: $problem']);
    stdout.writeln('${found.isEmpty ? 'ok  ' : 'FAIL'} ${file.path}');
  }
  if (check.tooFew(files.length) case final tooFew?) problems.add(tooFew);
  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }
  stdout.writeln('${files.length} case reports as expected.');
}

({CaseCheck check, String runs}) _parse(List<String> args) {
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
        fallbackPlatform = _cli.value(rest);

      case '--own':
        isOwn = true;

      case '--min-cases':
        minCases =
            int.tryParse(_cli.value(rest)) ??
            _cli.failUsage('--min-cases needs a number.');

      case '--outcome':
        outcomes.add(_cli.value(rest));

      case '--run-id':
        runId = _cli.value(rest);

      case '-h' || '--help':
        _cli.help();

      case final other when other.startsWith('-'):
        _cli.failUsage('unexpected argument $other.');

      case final directory:
        positional.add(directory);
    }
  }
  final runs = positional.singleOrNull;
  if (runs == null || isOwn == (fallbackPlatform != null)) {
    _cli.failUsage(
      'pass a runs directory and one of --fallback-platform or --own.',
    );
  }

  return (
    check: CaseCheck(
      fallbackPlatform: fallbackPlatform,
      minCases: minCases,
      outcomes: outcomes.isEmpty ? CaseCheck.defaultOutcomes : outcomes,
      runId: runId,
    ),
    runs: runs,
  );
}
