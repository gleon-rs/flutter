import 'dart:io';

/// A crate linked into the `gleon-ffi` library, with its license texts
/// (`bin/native_licenses.dart`).
///
/// Plain Dart (no Flutter imports): maintainer tooling, tested directly.
final class LicenseCrate {
  /// A crate [name] of [version] under [license] with its license [texts].
  const LicenseCrate({
    required this.license,
    required this.name,
    required this.repository,
    required this.texts,
    required this.version,
  });

  /// The SPDX expression; null when the crate names only a license file.
  final String? license;

  /// The crate name.
  final String name;

  /// Where its source lives, if known.
  final String? repository;

  /// Its license files, verbatim (line ends normalized).
  final List<String> texts;

  /// The crate version.
  final String version;

  /// The licenses that need no notice in a binary.
  static const _noticeFree = {
    '0BSD',
    'BSL-1.0',
    'CC0-1.0',
    'MIT-0',
    'Unlicense',
    'Zlib',
  };

  /// License files in a crate's root.
  static final _licenseFile = RegExp(
    '^(licen[cs]e|copying|notice|unlicense)',
    caseSensitive: false,
  );

  /// A line of `cargo tree --prefix none --format {p}`: `name vX.Y.Z ...`.
  static final _treeLine = RegExp(r'^(\S+) v(\S+)', multiLine: true);

  /// `name version`.
  String get label => '$name $version';

  /// The license of the expression that needs no notice, if any.
  String? get noticeFree => license
      ?.split(RegExp(r'\s+OR\s+|/'))
      .map((option) => option.trim())
      .where(_noticeFree.contains)
      .firstOrNull;

  /// The license as the table of `NATIVE_LICENSES.md` shows it.
  String get shownLicense => switch ((license, noticeFree)) {
    (null, _) => 'see license file',
    (final spdx?, final free?) when texts.isEmpty =>
      '$spdx ($free, which needs no notice)',
    (final spdx?, _) => spdx,
  };

  /// `name version` of every crate in the [output] of `cargo tree --prefix
  /// none --format {p}`.
  static Set<String> treeLabels(String output) => {
    for (final RegExpMatch(:group) in _treeLine.allMatches(output))
      if ((group(1), group(2)) case (final crate?, final version?))
        '$crate $version',
  };

  /// The crates of `cargo metadata` ([metadata], decoded JSON) whose labels
  /// are [labels], sorted by label.
  ///
  /// Throws a [FormatException] when [metadata] has no packages or lacks one
  /// of [labels], and for a crate whose license cannot be read (see [of]).
  static List<LicenseCrate> linked(Object? metadata, Set<String> labels) {
    final packages = switch (metadata) {
      {'packages': final List<Object?> list} => list,
      _ => throw const FormatException('cargo metadata printed no packages.'),
    };
    final sorted = [
      for (final package in packages)
        if (package
            case {'name': final String crate, 'version': final String version}
            when labels.contains('$crate $version'))
          ?of(package),
    ]..sort((a, b) => a.label.compareTo(b.label));
    final found = {for (final crate in sorted) crate.label};
    if (found.length != labels.length) {
      throw FormatException(
        'cargo metadata lacks ${labels.difference(found).join(', ')}.',
      );
    }

    return sorted;
  }

  /// The crate a `cargo metadata` [package] describes, with the license
  /// files in its root and its `license_file`, each read once; null when
  /// [package] is no package.
  ///
  /// Throws a [FormatException] naming the crate when its `license_file`
  /// does not exist, or when it has neither `license` nor `license_file`.
  static LicenseCrate? of(Object? package) {
    if (package case {
      'manifest_path': final String manifest,
      'name': final String crate,
      'version': final String version,
    }) {
      final label = '$crate $version';
      final license = switch (package['license']) {
        final String spdx => spdx.trim(),
        _ => null,
      };
      final licenseFile = package['license_file'];
      if (license == null && licenseFile is! String) {
        throw FormatException('$label has neither license nor license_file.');
      }

      return .new(
        license: license,
        name: crate,
        repository: package['repository']?.toString(),
        texts: _texts(File(manifest).parent, label, licenseFile),
        version: version,
      );
    }

    return null;
  }

  /// The license files in [root] and its [licenseFile], each read once
  /// (paths are compared canonical, so `./LICENSE` or `\` separators do
  /// not read a file twice).
  static List<String> _texts(
    Directory root,
    String label,
    Object? licenseFile,
  ) {
    final paths = <String>{
      for (final file in root.listSync().whereType<File>())
        if (_licenseFile.hasMatch(file.uri.pathSegments.lastOrNull ?? _none))
          file.resolveSymbolicLinksSync(),
      if (licenseFile case final String relative)
        _canonical(root, label, relative),
    }.toList()..sort();

    return [
      for (final path in paths)
        File(path).readAsStringSync().replaceAll('\r\n', '\n').trimRight(),
    ];
  }

  /// The canonical path of the [relative] `license_file` of the crate
  /// [label] in [root].
  static String _canonical(Directory root, String label, String relative) {
    final file = File.fromUri(
      root.absolute.uri.resolve(relative.replaceAll(r'\', '/')),
    );
    if (!file.existsSync()) {
      throw FormatException(
        '$label: its license_file $relative does not exist (${file.path}).',
      );
    }

    return file.resolveSymbolicLinksSync();
  }

  static const _none = '';
}
