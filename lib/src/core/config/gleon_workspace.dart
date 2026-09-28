import 'dart:io';

import 'package:meta/meta.dart';

import 'gleon_config_exception.dart';

/// A gleon workspace: the directory containing `.gleon/gleon.yaml`, the same
/// file the gleon CLI reads.
@immutable
final class GleonWorkspace {
  /// Creates a workspace rooted at [root] with the [configText] of
  /// [configFile].
  const GleonWorkspace({
    required this.root,
    required this.configFile,
    required this.configText,
  });

  /// The workspace root (the parent of `.gleon/`), with symbolic links
  /// resolved.
  final Directory root;

  /// `.gleon/gleon.yaml`.
  final File configFile;

  /// Contents of [configFile], read once.
  final String configText;

  /// `.gleon/`.
  Directory get gleonDir => .new('${root.path}/.gleon');

  /// `.gleon/runs/latest/cases/`, where case reports go.
  Directory get casesDir => .new('${gleonDir.path}/runs/latest/cases');

  /// Walks up from [start] (inclusive) like the CLI's `find_workspace_root`
  /// and returns the first directory with a `.gleon/gleon.yaml` file, or null.
  ///
  /// Throws a [GleonConfigException] naming the file when it cannot be read
  /// (e.g. it is not UTF-8).
  static GleonWorkspace? find(Directory start) {
    Directory dir = Directory(start.absolute.resolveSymbolicLinksSync());
    while (true) {
      final config = File('${dir.path}/.gleon/gleon.yaml');
      if (config.existsSync()) {
        final String text;
        try {
          text = config.readAsStringSync();
        } on FileSystemException catch (error, stackTrace) {
          Error.throwWithStackTrace(
            GleonConfigException(config.path, 'cannot read it: $error'),
            stackTrace,
          );
        }

        return GleonWorkspace(root: dir, configFile: config, configText: text);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }

  /// The path of [file] relative to [root] with `/` separators, or null when
  /// [file] is outside the workspace. [file] must exist.
  String? relativePath(File file) {
    final path = file.absolute.resolveSymbolicLinksSync();
    final rootPath = root.path;
    final separator = Platform.pathSeparator;
    final prefix = rootPath.endsWith(separator)
        ? rootPath
        : '$rootPath$separator';
    final inside = RegExp(
      '^${RegExp.escape(prefix)}(.+)\$',
      // Windows paths are case-insensitive; the CLI folds case for names too.
      caseSensitive: !Platform.isWindows,
    ).firstMatch(path)?.group(1);

    return inside?.replaceAll(r'\', '/');
  }
}
