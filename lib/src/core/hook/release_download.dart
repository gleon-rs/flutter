import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'atomic_write.dart';
import 'native_download_exception.dart';
import 'native_target.dart';

typedef _Checksums = ({Map<String, String> hashes, bool isCached});

/// Downloads, verifies and caches the prebuilt `gleon-ffi` library from a
/// GitHub Release. Plain Dart (no Flutter imports): used by `hook/build.dart`
/// and tested directly.
///
/// Trust model: releases of this repository are immutable (assets and tag can
/// never change after publishing), so `SHA256SUMS.txt` of a release pins the
/// bytes of its libraries. Every file is verified before it is used, and cached
/// content-addressed by its hash, so different versions never clash.
abstract final class ReleaseDownload {
  /// Name of the checksum file attached to every release.
  static const checksumsFileName = 'SHA256SUMS.txt';

  /// Where the release assets of package [version] live.
  static Uri defaultUrl(String version) => .parse(
    'https://github.com/gleon-rs/flutter/releases/download/v$version/',
  );

  /// Reads `version:` from the package's own `pubspec.yaml` [content].
  static String? readPubspecVersion(String content) => RegExp(
    "^version:\\s*[\"']?([^\\s\"'#]+)",
    multiLine: true,
  ).firstMatch(content)?.group(1);

  /// Parses `sha256sum` output (`<hex>  <name>` per line) into name → hash.
  static Map<String, String> parseChecksums(String content) => {
    for (final RegExpMatch(:group) in RegExp(
      r'^([0-9a-fA-F]{64})\s+\*?(\S+)\s*$',
      multiLine: true,
    ).allMatches(content))
      if ((group(2), group(1)) case (final name?, final hash?))
        name: hash.toLowerCase(),
  };

  /// Returns the verified library for [target] from the release of this
  /// package's [packageVersion] at [releaseUrl], downloading it into
  /// [cacheDir] only if no verified copy is cached yet.
  ///
  /// The checksum list is cached per URL and version, so a mirror kept across
  /// upgrades is asked again; a cached list that disagrees with the mirror
  /// (an entry missing, or a library with another hash) is reloaded once.
  ///
  /// [redirectTimeout] bounds reading the body of a redirect response,
  /// [bodyTimeout] reading a downloaded file.
  static Future<File> fetchLibrary({
    required Uri releaseUrl,
    required String packageVersion,
    required NativeTarget target,
    required Directory cacheDir,
    Duration redirectTimeout = const Duration(seconds: 30),
    Duration bodyTimeout = const Duration(minutes: 3),
  }) async {
    if (!_Release.isAllowedUrl(releaseUrl)) {
      throw NativeDownloadException(
        'release_url must be an https URL (plain http only for localhost), '
        'got "$releaseUrl". For a library file on disk, set the `ffi_path` '
        'user-define instead.',
      );
    }
    final fetch = _Release(
      url: releaseUrl,
      packageVersion: packageVersion,
      cacheDir: cacheDir,
      redirectTimeout: redirectTimeout,
      bodyTimeout: bodyTimeout,
    );
    try {
      return await fetch.library(target);
    } finally {
      fetch.close();
    }
  }
}

/// One release being fetched: its URL, the local cache and the HTTP client.
final class _Release {
  _Release({
    required this.url,
    required this.packageVersion,
    required this.cacheDir,
    required this.redirectTimeout,
    required this.bodyTimeout,
  });

  final Uri url;
  final String packageVersion;
  final Directory cacheDir;
  final Duration redirectTimeout;
  final Duration bodyTimeout;

  static const _overridesHint =
      'Alternatively set the `ffi_path` user-define to a local copy of the '
      'library, `release_url` to a mirror of the release, or `gleon_repo` to '
      'build it from a gleon checkout (see the package README).';

  static const _attempts = 3;
  static const _maxRedirects = 5;

  final _client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = const Duration(seconds: 30)
    ..userAgent = 'gleon-flutter-build-hook';

  /// Only https, or plain http to this machine (local mirrors and tests): the
  /// checksum list travels the same way as the libraries, so an insecure hop
  /// would let an attacker replace both.
  static bool isAllowedUrl(Uri url) =>
      url.isScheme('https') ||
      (url.isScheme('http') &&
          const {'localhost', '127.0.0.1', '::1'}.contains(url.host));

  /// Whether [url] is a `release_url` mirror rather than this package's
  /// GitHub Release.
  bool get isMirror => url != ReleaseDownload.defaultUrl(packageVersion);

  /// What a mirror must serve, for errors that a stale mirror would explain.
  String get _mirrorHint => isMirror
      ? ' The `release_url` user-define ($url) must serve the release of '
            'gleon $packageVersion unchanged.'
      : _noHint;

  static const _noHint = '';

  void close() => _client.close(force: true);

  Future<File> library(NativeTarget target) async {
    _Checksums checksums = await _checksums();
    if (checksums.hashes[target.assetName] == null && checksums.isCached) {
      // A cached list can only be stale for a mirror.
      checksums = await _checksums(isRefresh: true);
    }
    String expected = _expected(checksums, target);
    File library = _cachedLibrary(expected, target);
    if (library.existsSync() &&
        await AtomicWrite.sha256Of(library) == expected) {
      return library;
    }
    final assetUrl = url.resolve(target.assetName);
    final bytes = await _download(assetUrl);
    final actual = sha256.convert(bytes).toString();
    if (actual != expected && checksums.isCached) {
      // The mirror may have changed since its list was cached.
      checksums = await _checksums(isRefresh: true);
      expected = _expected(checksums, target);
      library = _cachedLibrary(expected, target);
    }
    if (actual != expected) {
      throw NativeDownloadException(
        'checksum mismatch for $assetUrl (expected $expected per '
        '$_checksumsUrl, got $actual). The file was not used.'
        '$_mirrorHint',
      );
    }
    await AtomicWrite.bytes(library, bytes, expectedSha256: expected);

    return library;
  }

  /// The hash of [target]'s library in [checksums].
  String _expected(_Checksums checksums, NativeTarget target) =>
      checksums.hashes[target.assetName] ??
      (throw NativeDownloadException(
        'the release at $url has no ${target.assetName} for '
        '${target.key} in its ${ReleaseDownload.checksumsFileName}.'
        '$_mirrorHint',
      ));

  /// Where the library of [target] with the hash [expected] is cached.
  File _cachedLibrary(String expected, NativeTarget target) =>
      .fromUri(cacheDir.uri.resolve('$expected/${target.libFileName}'));

  Uri get _checksumsUrl => url.resolve(ReleaseDownload.checksumsFileName);

  /// The checksum list of the release: cached unless [isRefresh], which
  /// replaces a cached copy.
  Future<_Checksums> _checksums({bool isRefresh = false}) async {
    final checksumsUrl = _checksumsUrl;
    // Per version too: a mirror URL may stay the same across upgrades.
    final key = sha256.convert(utf8.encode('$checksumsUrl\n$packageVersion'));
    final file = File.fromUri(cacheDir.uri.resolve('checksums/$key.txt'));
    // A refresh replaces the cached list atomically below: deleting it first
    // would let a concurrent build find no list at all.
    if (!isRefresh && file.existsSync()) {
      final content = await file.readAsString();

      return (hashes: ReleaseDownload.parseChecksums(content), isCached: true);
    }
    final bytes = await _download(checksumsUrl);
    final hashes = ReleaseDownload.parseChecksums(
      utf8.decode(bytes, allowMalformed: true),
    );
    if (hashes.isEmpty) {
      throw NativeDownloadException(
        '$checksumsUrl is not a valid checksum list.',
      );
    }
    await AtomicWrite.bytes(file, bytes);

    return (hashes: hashes, isCached: false);
  }

  /// GETs [source], retrying transient failures with a linear backoff.
  Future<List<int>> _download(Uri source) async {
    for (int attempt = 1; ; attempt += 1) {
      final bytes = await _attempt(source, isLast: attempt == _attempts);
      if (bytes != null) return bytes;
      // Linear backoff before retrying a transient failure.
      await Future<void>.delayed(Duration(seconds: attempt));
    }
  }

  /// One GET of [source]: the body, or null for a transient failure that
  /// should be retried unless this [isLast] attempt.
  Future<List<int>?> _attempt(Uri source, {required bool isLast}) async {
    try {
      final response = await _get(source);
      final status = response.statusCode;
      if (status == HttpStatus.ok) {
        final builder = BytesBuilder(copy: false);
        await _read(response, response.forEach(builder.add), bodyTimeout);

        return builder.takeBytes();
      }
      // An error page is never needed: drop it instead of reading it.
      await _drain(response);
      if (status == HttpStatus.notFound) {
        throw NativeDownloadException(
          isMirror
              ? '$source does not exist (HTTP 404).$_mirrorHint '
                    '$_overridesHint'
              : '$source does not exist (HTTP 404). Prebuilt libraries are '
                    'attached to tagged releases only: depend on a released '
                    'version (git `ref: vX.Y.Z`) rather than an untagged '
                    'commit. $_overridesHint',
        );
      }
      if (status < HttpStatus.internalServerError || isLast) {
        throw NativeDownloadException(
          'downloading $source failed with HTTP $status. $_overridesHint',
        );
      }
    } on NativeDownloadException {
      rethrow;
    } on Exception catch (error, stackTrace) {
      // SocketException, HttpException, TimeoutException, TLS errors, ...
      if (isLast) {
        Error.throwWithStackTrace(
          NativeDownloadException(
            'could not download $source ($error). Check the network or proxy '
            '(HTTPS_PROXY is honored), or download the file manually. '
            '$_overridesHint',
          ),
          stackTrace,
        );
      }
    }

    return null;
  }

  /// Sends a GET to [source] and follows redirects itself, checking every
  /// target with [isAllowedUrl] so a redirect can never downgrade to plain
  /// http.
  Future<HttpClientResponse> _get(Uri source) async {
    Uri current = source;
    for (int redirects = 0; ; redirects += 1) {
      final request = await _client.getUrl(current)
        ..followRedirects = false;
      final response = await request.close().timeout(
        const Duration(minutes: 1),
      );
      if (!response.isRedirect) return response;
      await _drain(response);
      final location =
          response.headers.value(HttpHeaders.locationHeader) ??
          (throw NativeDownloadException(
            'downloading $source failed: redirect without a location.',
          ));
      if (redirects == _maxRedirects) {
        throw NativeDownloadException(
          'downloading $source failed: more than $_maxRedirects redirects.',
        );
      }
      final next = current.resolve(location);
      if (!isAllowedUrl(next)) {
        throw NativeDownloadException(
          '$source redirected to $next; refusing to download over an '
          'insecure connection.',
        );
      }
      current = next;
    }
  }

  /// Discards a body that is never used (redirects, error pages).
  Future<void> _drain(HttpClientResponse response) =>
      _read(response, response.drain<void>(), redirectTimeout);

  /// Waits for [reading] the body of [response] at most [timeout], dropping
  /// the connection if it stalls, so a retry never reuses it (the retry loop
  /// in [_download] then reports the timeout).
  static Future<void> _read(
    HttpClientResponse response,
    Future<void> reading,
    Duration timeout,
  ) async {
    try {
      await reading.timeout(timeout);
    } on TimeoutException {
      // If the connection is already gone, that error is retried instead.
      final socket = await response.detachSocket();
      socket.destroy();

      rethrow;
    }
  }
}
