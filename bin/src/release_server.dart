/// A release of the native library over loopback HTTP, as the build hook
/// expects one: the assets under their release names and the
/// `SHA256SUMS.txt` the hook verifies them against (`sha256sum -- *`), like a
/// GitHub Release or a mirror named by the `release_url` user-define serves
/// them. Only `dart:*` and `crypto` are imported here.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A local release: a directory of assets served at [url].
final class ReleaseServer {
  ReleaseServer._(this._server, this._assets, this.checksums);

  /// The checksum list of a release.
  static const checksumsFileName = 'SHA256SUMS.txt';

  /// The `SHA256SUMS.txt` of the assets.
  final String checksums;

  /// The paths requested so far, in order.
  List<String> requests = const [];

  final HttpServer _server;

  /// Release asset name → bytes.
  final Map<String, List<int>> _assets;

  StreamSubscription<HttpRequest>? _subscription;

  /// Serves [assets] (release asset name → file) on a free loopback port,
  /// read once now.
  static Future<ReleaseServer> start(Map<String, File> assets) async {
    final bytes = {
      for (final MapEntry(key: name, value: file) in assets.entries)
        name: file.readAsBytesSync(),
    };
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = ReleaseServer._(server, bytes, checksumsOf(bytes));
    release._subscription = server.listen(release._serve);

    return release;
  }

  /// `sha256sum -- *` of [assets] (`<hex>  <name>` per line, by name).
  static String checksumsOf(Map<String, List<int>> assets) {
    final sorted = SplayTreeMap<String, List<int>>.of(assets);

    return [
      for (final MapEntry(key: name, value: bytes) in sorted.entries)
        '${sha256.convert(bytes)}  $name\n',
    ].join();
  }

  /// The directory of the release, the `release_url` of a consumer:
  /// `http://127.0.0.1:<port>/` (plain HTTP is allowed to the loopback
  /// address only).
  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/');

  /// Stops serving; pending requests are dropped.
  Future<void> close() async {
    await _subscription?.cancel();
    await _server.close(force: true);
  }

  /// Answers [request] with the checksum list, an asset or 404. A client that
  /// hangs up (a hook timing out, a dropped connection) is no failure of the
  /// release and must not crash the check.
  void _serve(HttpRequest request) {
    final HttpRequest(:response, :uri) = request;
    final name = uri.pathSegments.join('/');
    requests = [...requests, name];
    if (name == checksumsFileName) {
      response
        ..headers.contentType = .text
        ..write(checksums);
    } else if (_assets[name] case final bytes?) {
      response
        ..headers.contentType = .binary
        ..contentLength = bytes.length
        ..add(bytes);
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    unawaited(_close(response));
  }

  /// Sends [response]; see [_serve].
  static Future<void> _close(HttpResponse response) async {
    try {
      await response.close();
    } on IOException {
      // The client is gone: nothing left to send it.
    }
  }
}
