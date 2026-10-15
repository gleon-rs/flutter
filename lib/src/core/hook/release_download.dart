import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import 'atomic_write.dart';
import 'native_target.dart';
import 'network_failure.dart';

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

  /// Name of the file of a release that names the gleon commit its libraries
  /// were built from (`native/gleon_ref` of its tag), listed in its
  /// [checksumsFileName]; releases before 0.5.0 have none.
  static const pinFileName = 'gleon_ref.txt';

  /// Where the release assets of package [version] live.
  static Uri defaultUrl(String version) => .parse(
    'https://github.com/gleon-rs/flutter/releases/download/v$version/',
  );

  /// Reads `version:` from the package's own `pubspec.yaml` [content].
  static String? readPubspecVersion(String content) => RegExp(
    "^version:\\s*[\"']?([^\\s\"'#]+)",
    multiLine: true,
  ).firstMatch(content)?.group(1);

  /// The proxy of [url] in [environment] (`HTTPS_PROXY`, `NO_PROXY`, ...):
  /// none for this machine, where a local mirror lives, whatever the
  /// environment says (`HttpClient.findProxyFromEnvironment` sends it to the
  /// proxy unless `NO_PROXY` names it).
  @visibleForTesting
  static String proxyFor(Uri url, Map<String, String> environment) =>
      isThisMachine(url)
      ? 'DIRECT'
      : HttpClient.findProxyFromEnvironment(url, environment: environment);

  /// Whether [url] names this machine: `localhost` or a loopback address
  /// (all of 127.0.0.0/8, where Debian names the host 127.0.1.1, and ::1).
  static bool isThisMachine(Uri url) =>
      url.host == 'localhost' ||
      (InternetAddress.tryParse(url.host)?.isLoopback ?? false);

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
  /// A checkout of the package (a git dependency) passes its [pin]
  /// (`native/gleon_ref`): a release whose libraries were built from another
  /// commit fails, since its engine is not the one the checkout expects.
  ///
  /// [redirectTimeout] bounds reading the body of a redirect response,
  /// [bodyTimeout] a pause in a downloaded file (a slow but steady download
  /// goes on), [maxBytes] its size (no library comes near).
  static Future<File> fetchLibrary({
    required Uri releaseUrl,
    required String packageVersion,
    required NativeTarget target,
    required Directory cacheDir,
    String? pin,
    Duration redirectTimeout = const Duration(seconds: 30),
    Duration bodyTimeout = const Duration(minutes: 1),
    int maxBytes = 64 << 20,
  }) async {
    if (!_Release.isAllowedUrl(releaseUrl)) {
      throw StateError(
        'gleon: release_url must be an https URL (plain http only to this '
        'machine), got '
        '"${releaseUrl.replace(userInfo: _Release._none)}". For a '
        'library file on disk, set the `ffi_path` user-define instead.',
      );
    }
    final fetch = _Release(
      url: releaseUrl,
      packageVersion: packageVersion,
      cacheDir: cacheDir,
      redirectTimeout: redirectTimeout,
      bodyTimeout: bodyTimeout,
      maxBytes: maxBytes,
    );
    try {
      return await fetch.library(target, pin: pin);
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
    required this.maxBytes,
  });

  final Uri url;
  final String packageVersion;
  final Directory cacheDir;
  final Duration redirectTimeout;
  final Duration bodyTimeout;
  final int maxBytes;

  static const _overridesHint =
      'Alternatively set the `ffi_path` user-define to a local copy of the '
      'library, `release_url` to a mirror of the release, or `gleon_repo` to '
      'build it from a gleon checkout (see the package README).';

  /// A download or verification failure with an actionable [message]; hook
  /// errors are printed verbatim, without the credentials a mirror URL may
  /// hold ([_redacted]).
  StateError failure(String message) => .new('gleon: ${_redacted(message)}');

  /// [failure] for a download the network failed ([NetworkFailure]).
  NetworkFailure networkFailure(String message) =>
      .new('gleon: ${_redacted(message)}');

  /// [message] without the user and password of any URL in it (a private
  /// mirror, a redirect), which logs must never show.
  static String _redacted(String message) =>
      message.replaceAllMapped(_userInfo, (match) => match.group(1) ?? _none);

  /// The user and password of a URL (`scheme://user:password@`), after its
  /// scheme (group 1).
  static final _userInfo = RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@\s]+@');

  static const _attempts = 3;
  static const _maxRedirects = 5;

  final _client = HttpClient()
    ..findProxy = ((url) => ReleaseDownload.proxyFor(url, Platform.environment))
    ..connectionTimeout = const Duration(seconds: 30)
    ..userAgent = 'gleon-flutter-build-hook';

  /// Only https, or plain http to this machine (local mirrors and tests): the
  /// checksum list travels the same way as the libraries, so an insecure hop
  /// would let an attacker replace both.
  static bool isAllowedUrl(Uri url) =>
      url.isScheme('https') ||
      (url.isScheme('http') && ReleaseDownload.isThisMachine(url));

  /// Whether [url] is a `release_url` mirror rather than this package's
  /// GitHub Release.
  bool get isMirror => url != ReleaseDownload.defaultUrl(packageVersion);

  /// What a mirror must serve, for errors that a stale mirror would explain.
  String get _mirrorHint => isMirror
      ? ' The `release_url` user-define ($url) must serve the release of '
            'gleon $packageVersion unchanged.'
      : _none;

  /// Nothing: no hint, no user and password in a shown URL.
  static const _none = '';

  void close() => _client.close(force: true);

  /// The verified library of [target]; the release must have been built
  /// from [pin] when one is given and the release names its own.
  Future<File> library(NativeTarget target, {String? pin}) async {
    final (:file, :checksums) = await _library(target);
    if (pin != null) await _checkPin(pin, checksums);

    return file;
  }

  /// Fails unless the release names no pin or [pin]: its libraries were
  /// built from another gleon commit than the checkout's.
  Future<void> _checkPin(String pin, _Checksums checksums) async {
    final expected = checksums.hashes[ReleaseDownload.pinFileName];
    if (expected == null) return;
    final cached = File.fromUri(
      cacheDir.uri.resolve('$expected/${ReleaseDownload.pinFileName}'),
    );
    final List<int> bytes;
    if (cached.existsSync() && await AtomicWrite.sha256Of(cached) == expected) {
      bytes = cached.readAsBytesSync();
    } else {
      final source = url.resolve(ReleaseDownload.pinFileName);
      bytes = await _download(source);
      if (sha256.convert(bytes).toString() != expected) {
        throw failure(
          'checksum mismatch for $source (expected $expected per '
          '$_checksumsUrl). The file was not used.$_mirrorHint',
        );
      }
      await AtomicWrite.bytes(cached, bytes, expectedSha256: expected);
    }
    final released = utf8.decode(bytes, allowMalformed: true).trim();
    if (released != pin) {
      throw failure(
        'this checkout of the package pins gleon $pin (native/gleon_ref), but '
        'the release v$packageVersion at $url was built from gleon '
        '$released: its engine is not the one this checkout expects. Depend '
        'on a released version (git `ref: v$packageVersion`, or the tag of a '
        'later release), whose libraries match its pin. $_overridesHint',
      );
    }
  }

  /// The verified library of [target] and the checksum list that verified
  /// it.
  Future<({_Checksums checksums, File file})> _library(
    NativeTarget target,
  ) async {
    _Checksums checksums = await _checksums();
    if (checksums.hashes[target.assetName] == null && checksums.isCached) {
      // A cached list can only be stale for a mirror.
      checksums = await _checksums(isRefresh: true);
    }
    String expected = _expected(checksums, target);
    File library = _cachedLibrary(expected, target);
    if (library.existsSync() &&
        await AtomicWrite.sha256Of(library) == expected) {
      return (checksums: checksums, file: library);
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
      throw failure(
        'checksum mismatch for $assetUrl (expected $expected per '
        '$_checksumsUrl, got $actual). The file was not used.'
        '$_mirrorHint',
      );
    }
    await AtomicWrite.bytes(library, bytes, expectedSha256: expected);

    return (checksums: checksums, file: library);
  }

  /// The hash of [target]'s library in [checksums].
  String _expected(_Checksums checksums, NativeTarget target) =>
      checksums.hashes[target.assetName] ??
      (throw failure(
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
      throw failure('$checksumsUrl is not a valid checksum list.');
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
      if (status == HttpStatus.ok) return await _body(response, source);
      // An error page is never needed: drop it instead of reading it.
      await _drain(response);
      if (status == HttpStatus.notFound) {
        throw failure(
          isMirror
              ? '$source does not exist (HTTP 404).$_mirrorHint '
                    '$_overridesHint'
              : '$source does not exist (HTTP 404). Prebuilt libraries are '
                    'attached to tagged releases only: depend on a released '
                    'version (git `ref: vX.Y.Z`) rather than an untagged '
                    'commit. $_overridesHint',
        );
      }
      // A failing or busy server, or one that timed out the request.
      final isTransient =
          status >= HttpStatus.internalServerError ||
          status == HttpStatus.tooManyRequests ||
          status == HttpStatus.requestTimeout;
      if (!isTransient || isLast) {
        final message =
            'downloading $source failed with HTTP $status. $_overridesHint';

        throw isTransient ? networkFailure(message) : failure(message);
      }
    } on Exception catch (error, stackTrace) {
      // SocketException, HttpException, TimeoutException, TLS errors, ...
      if (isLast) {
        Error.throwWithStackTrace(
          networkFailure(
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
          (throw failure(
            'downloading $source failed: redirect without a location.',
          ));
      if (redirects == _maxRedirects) {
        throw failure(
          'downloading $source failed: more than $_maxRedirects redirects.',
        );
      }
      final next = current.resolve(location);
      if (!isAllowedUrl(next)) {
        throw failure(
          '$source redirected to $next; refusing to download over an '
          'insecure connection.',
        );
      }
      current = next;
    }
  }

  /// The body of [response] from [source]: at most [maxBytes], with no pause
  /// longer than [bodyTimeout] between its parts. A stalled body drops its
  /// connection, so a retry never reuses it (the retry loop in [_download]
  /// then reports the timeout).
  Future<List<int>> _body(HttpClientResponse response, Uri source) async {
    final tooLarge = failure(
      '$source sends more than $maxBytes bytes, more than any library: '
      'refused.$_mirrorHint',
    );
    if (response.contentLength > maxBytes) {
      await _drop(response);

      throw tooLarge;
    }
    final builder = BytesBuilder(copy: false);
    try {
      await for (final part in response.timeout(bodyTimeout)) {
        builder.add(part);
        if (builder.length > maxBytes) throw tooLarge;
      }
    } on TimeoutException {
      await _drop(response);

      rethrow;
    }

    return builder.takeBytes();
  }

  /// Closes the connection of [response] for good.
  static Future<void> _drop(HttpClientResponse response) async {
    final socket = await response.detachSocket();
    socket.destroy();
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
      await _drop(response);

      rethrow;
    }
  }
}
