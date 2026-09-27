// Downloads, verifies and caches the prebuilt `gleon-ffi` library from a
// GitHub Release. Plain Dart (no Flutter imports): used by `hook/build.dart`
// and tested directly.
//
// Trust model: releases of this repository are immutable (assets and tag can
// never change after publishing), so `SHA256SUMS.txt` of a release pins the
// bytes of its libraries. Every file is verified before it is used, and cached
// content-addressed by its hash, so different versions never clash.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'targets.dart';

/// Name of the checksum file attached to every release.
const checksumsFileName = 'SHA256SUMS.txt';

/// Where the release assets of package [version] live.
Uri defaultReleaseUrl(String version) => Uri.parse(
  'https://github.com/gleon-rs/flutter/releases/download/v$version/',
);

/// Reads `version:` from the package's own `pubspec.yaml` [content].
String? readPubspecVersion(String content) => RegExp(
  r'^version:\s*["\x27]?([^\s"\x27#]+)',
  multiLine: true,
).firstMatch(content)?.group(1);

/// Parses `sha256sum` output (`<hex>  <name>` per line) into name → hash.
Map<String, String> parseChecksums(String content) => {
  for (final match in RegExp(
    r'^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$',
    multiLine: true,
  ).allMatches(content))
    match.group(2)!: match.group(1)!.toLowerCase(),
};

/// A download or verification failure with an actionable message.
class NativeDownloadException implements Exception {
  /// Creates the exception.
  NativeDownloadException(this.message);

  /// Human-readable reason, including what to do about it.
  final String message;

  @override
  String toString() => 'gleon: $message';
}

const _overridesHint =
    'Alternatively set the `ffi_path` user-define to a local copy of the '
    'library, or `gleon_repo` to build it from a gleon checkout (see the '
    'package README).';

/// Returns the verified library for [target] from the release at [releaseUrl],
/// downloading it into [cacheDir] only if no verified copy is cached yet.
Future<File> fetchReleaseLibrary({
  required Uri releaseUrl,
  required NativeTarget target,
  required Directory cacheDir,
}) async {
  if (releaseUrl.scheme != 'https' && releaseUrl.scheme != 'http') {
    throw NativeDownloadException(
      'release_url must be an http(s) URL, got "$releaseUrl". For a library '
      'file on disk, set the `ffi_path` user-define instead.',
    );
  }
  final client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = const Duration(seconds: 30)
    ..userAgent = 'gleon-flutter-build-hook';
  try {
    final checksums = await _checksums(client, releaseUrl, cacheDir);
    var expected = checksums.hashes[target.assetName];
    if (expected == null && checksums.fromCache) {
      // A cached list can only be stale for a custom, mutable `release_url`.
      await checksums.file.delete();
      expected = (await _checksums(
        client,
        releaseUrl,
        cacheDir,
      )).hashes[target.assetName];
    }
    if (expected == null) {
      throw NativeDownloadException(
        'the release at $releaseUrl has no ${target.assetName} for '
        '${target.key} in its $checksumsFileName.',
      );
    }

    final library = File.fromUri(
      cacheDir.uri.resolve('$expected/${target.libFileName}'),
    );
    if (library.existsSync() && await _sha256(library) == expected) {
      return library;
    }
    final bytes = await _download(client, releaseUrl.resolve(target.assetName));
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      throw NativeDownloadException(
        'checksum mismatch for ${releaseUrl.resolve(target.assetName)} '
        '(expected $expected, got $actual). The file was not used.',
      );
    }
    await _writeAtomically(library, bytes, expected: expected);
    return library;
  } finally {
    client.close(force: true);
  }
}

typedef _Checksums = ({Map<String, String> hashes, File file, bool fromCache});

Future<_Checksums> _checksums(
  HttpClient client,
  Uri releaseUrl,
  Directory cacheDir,
) async {
  final url = releaseUrl.resolve(checksumsFileName);
  final key = sha256.convert(utf8.encode(url.toString())).toString();
  final file = File.fromUri(
    cacheDir.uri.resolve('checksums/${key.substring(0, 16)}.txt'),
  );
  if (file.existsSync()) {
    return (
      hashes: parseChecksums(await file.readAsString()),
      file: file,
      fromCache: true,
    );
  }
  final bytes = await _download(client, url);
  final hashes = parseChecksums(utf8.decode(bytes, allowMalformed: true));
  if (hashes.isEmpty) {
    throw NativeDownloadException('$url is not a valid checksum list.');
  }
  await _writeAtomically(file, bytes);
  return (hashes: hashes, file: file, fromCache: false);
}

/// GETs [url] (following redirects), retrying transient failures.
Future<List<int>> _download(HttpClient client, Uri url) async {
  const attempts = 3;
  for (var attempt = 1; ; attempt++) {
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final bytes = await response
          .fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d))
          .timeout(const Duration(minutes: 3));
      if (response.statusCode == HttpStatus.ok) {
        return bytes.takeBytes();
      }
      if (response.statusCode == HttpStatus.notFound) {
        throw NativeDownloadException(
          '$url does not exist (HTTP 404). Prebuilt libraries are attached to '
          'tagged releases only: depend on a released version (git `ref: '
          'vX.Y.Z`) rather than an untagged commit. $_overridesHint',
        );
      }
      if (response.statusCode < 500 || attempt == attempts) {
        throw NativeDownloadException(
          'downloading $url failed with HTTP ${response.statusCode}. '
          '$_overridesHint',
        );
      }
    } on NativeDownloadException {
      rethrow;
    } on Exception catch (error) {
      // SocketException, HttpException, TimeoutException, TLS errors, ...
      if (attempt == attempts) {
        throw NativeDownloadException(
          'could not download $url ($error). Check the network or proxy '
          '(HTTPS_PROXY is honored), or download the file manually. '
          '$_overridesHint',
        );
      }
    }
    await Future<void>.delayed(Duration(seconds: attempt));
  }
}

/// Writes [bytes] to [file] via a unique temp file and a rename, so
/// concurrent builds never observe a partial file.
Future<void> _writeAtomically(
  File file,
  List<int> bytes, {
  String? expected,
}) async {
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.${pid}_${Random().nextInt(1 << 32)}.tmp');
  await temp.writeAsBytes(bytes, flush: true);
  try {
    await temp.rename(file.path);
  } on FileSystemException {
    // Windows cannot replace a file another process has loaded; a concurrent
    // build that already stored the same verified bytes is fine.
    await temp.delete();
    final ok =
        file.existsSync() &&
        (expected == null || await _sha256(file) == expected);
    if (!ok) rethrow;
  }
}

Future<String> _sha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
