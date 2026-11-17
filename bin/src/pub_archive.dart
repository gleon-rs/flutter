/// The archive pub publishes of a package, packed offline as the release
/// workflow packs it (`dart pub publish --to-archive`): what consumers get is
/// read from pub itself, never from a list kept here next to `.pubignore`.
/// Only `dart:*` and this package may be imported here (see
/// `build_native.dart`).
library;

import 'dart:convert';
import 'dart:io';

import 'check_failure.dart';

/// The archive of a package, packed into [dir] as [fileName].
///
/// Its files and its extraction go through `tar` with paths relative to
/// [dir] only: the GNU tar of Git Bash on Windows reads `C:` as a host name.
final class PubArchive {
  const new _(this.dir);

  /// The name of the archive in [dir].
  static const fileName = 'package.tar.gz';

  /// The directory that holds the archive.
  final Directory dir;

  /// Packs the package in [package] into [dir], without validation (the
  /// checks of the callers come after).
  ///
  /// Throws a [CheckFailure] with the output of pub if it fails.
  static Future<PubArchive> pack(Directory package, Directory dir) async {
    final archive = '--to-archive=${dir.absolute.path}/$fileName';
    await _run('dart', [..._publish, archive], package);

    return ._(dir);
  }

  /// `dart pub publish` without validation (the checks of the callers come
  /// after), before `--to-archive`.
  static const _publish = ['pub', 'publish', '--skip-validation'];

  /// A leading `./` or a trailing `/` of an entry `tar` lists.
  static final _dotOrSlash = RegExp(r'^\./|/$');

  /// Nothing, in place of [_dotOrSlash].
  static const _none = '';

  /// The files of the archive, relative to the package root and
  /// `/`-separated ([filesOf] its listing).
  ///
  /// Throws a [CheckFailure] with the output of `tar` if it fails.
  // ignore: prefer-getter-over-method, it runs tar.
  Future<List<String>> files() async =>
      filesOf(await _run('tar', const ['-tzf', fileName], dir));

  /// The files of the archive `tar -t` lists in [listing]: its entries
  /// without a leading `./` and a trailing `/`, and without the directories
  /// (pub writes them without a trailing `/`; pub packs no empty one).
  static List<String> filesOf(String listing) {
    final entries = {
      for (final entry in LineSplitter.split(listing))
        if (entry.isNotEmpty) entry.replaceAll(_dotOrSlash, _none),
    };

    return [
      for (final entry in entries)
        if (!entries.any((other) => other.startsWith('$entry/'))) entry,
    ];
  }

  /// Extracts the archive into the new directory [name] of [dir] and returns
  /// it.
  ///
  /// Throws a [CheckFailure] with the output of `tar` if it fails.
  Future<Directory> extractInto(String name) async {
    final into = Directory('${dir.path}/$name')..createSync(recursive: true);
    await _run('tar', ['-xzf', fileName, '-C', name], dir);

    return into;
  }

  /// Runs [executable] with [arguments] in [workingDirectory] and returns its
  /// standard output; through the shell on Windows, where `dart` is a
  /// `.bat` file.
  static Future<String> _run(
    String executable,
    List<String> arguments,
    Directory workingDirectory,
  ) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw CheckFailure(
        '$executable ${arguments.join(' ')} failed with exit code '
        '${result.exitCode}:\n${result.stdout}\n${result.stderr}',
      );
    }

    return '${result.stdout}';
  }
}
