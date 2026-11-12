import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A local release mirror: serves [files] (name → bytes), answers [redirects]
/// (name → location), sends redirects whose body never arrives for [stalled]
/// and files whose body never arrives for [stalledFiles], sends the files of
/// [dripped] chunked in four parts with that pause before each, answers
/// [statuses] (name → bare status code) and counts requests per name in
/// [hits]. Files are sent with their size, like GitHub sends them.
class ReleaseServer {
  new _(
    this._server, {
    required this.files,
    required this.redirects,
    required this.stalled,
    required this.stalledFiles,
    required this.dripped,
    required this.statuses,
  });

  /// Served files by name; mutable to emulate a changing mirror.
  final Map<String, List<int>> files;

  /// Redirect locations by name.
  final Map<String, String> redirects;

  /// Names whose redirect body stalls.
  final Set<String> stalled;

  /// Names answered with 200 and a body that stalls.
  final Set<String> stalledFiles;

  /// Names whose body arrives in four parts, with this pause before each.
  final Map<String, Duration> dripped;

  /// Names answered with only a status code (no body, no headers).
  final Map<String, int> statuses;

  /// Requests per name.
  final hits = <String, int>{};

  /// The URLs the clients of [route] asked for, in order.
  final routed = <Uri>[];

  final HttpServer _server;

  StreamSubscription<HttpRequest>? _subscription;

  /// Base URL of the release (with a trailing slash).
  Uri get url => .parse('http://127.0.0.1:${_server.port}/v1.0.0/');

  /// Starts serving on a free loopback port.
  static Future<ReleaseServer> start(
    Map<String, List<int>> files, {
    Map<String, String> redirects = const {},
    Set<String> stalledRedirects = const {},
    Set<String> stalledFiles = const {},
    Map<String, Duration> dripped = const {},
    Map<String, int> statuses = const {},
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = ReleaseServer._(
      server,
      files: {...files},
      redirects: redirects,
      stalled: stalledRedirects,
      stalledFiles: stalledFiles,
      dripped: dripped,
      statuses: statuses,
    );
    release._subscription = server.listen(release._handle);

    return release;
  }

  /// Runs [body] with every [HttpClient] it creates sending its requests
  /// here instead, by file name, whatever their URL (recorded in [routed]):
  /// this release stands for one anywhere, such as the GitHub Release of
  /// the package.
  Future<T> route<T>(Future<T> Function() body) =>
      HttpOverrides.runWithHttpOverrides(body, _Routing(this));

  /// Stops the server.
  Future<void> close() async {
    await _subscription?.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final HttpRequest(:response, :uri) = request;
    final name = uri.pathSegments.lastOrNull ?? '/';
    hits[name] = (hits[name] ?? 0) + 1;
    if (stalled.contains(name)) {
      response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, 'elsewhere')
        ..contentLength = 1024
        ..add(const [0]);
      // The promised body never arrives; the client must give up.
      await response.flush();

      return;
    }
    if (stalledFiles.contains(name)) {
      response
        ..contentLength = 1024
        ..add(const [0]);
      // The promised body never arrives; the client must give up.
      await response.flush();

      return;
    }
    if ((files[name], dripped[name]) case (final body?, final pause?)) {
      // Chunked and unbuffered: each part leaves when it is flushed, and
      // nothing announces the size.
      response.bufferOutput = false;
      final part = (body.length / 4).ceil();
      for (int start = 0; start < body.length; start += part) {
        // A slow server: the client waits for each part.
        await Future.pause(pause);
        response.add(body.sublist(start, (start + part).clamp(0, body.length)));
        await response.flush();
      }
      await response.close();

      return;
    }
    if (statuses[name] case final status?) {
      response.statusCode = status;
      await response.close();

      return;
    }
    if (redirects[name] case final location?) {
      response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, location);
      await response.close();

      return;
    }
    final body = files[name];
    response
      ..statusCode = body == null ? HttpStatus.notFound : HttpStatus.ok
      ..contentLength = body?.length ?? 0;
    if (body != null) response.add(body);
    await response.close();
  }
}

/// The [HttpOverrides] of [ReleaseServer.route].
final class _Routing extends HttpOverrides {
  new(this._server);

  final ReleaseServer _server;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RoutedClient(super.createHttpClient(context), _server);
}

/// A [_client] whose GETs go to [_server], by file name, whatever their URL.
final class _RoutedClient extends Fake implements HttpClient {
  new(this._client, this._server);

  final HttpClient _client;
  final ReleaseServer _server;

  @override
  Duration? get connectionTimeout => _client.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _client.connectionTimeout = value;

  @override
  String? get userAgent => _client.userAgent;

  @override
  set userAgent(String? value) => _client.userAgent = value;

  // Asked for the URL of the server, on this machine.
  @override
  set findProxy(String Function(Uri url)? value) => _client.findProxy = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    _server.routed.add(url);

    return _client.getUrl(
      _server.url.resolveUri(Uri(path: url.pathSegments.lastOrNull)),
    );
  }

  @override
  void close({bool force = false}) => _client.close(force: force);
}
