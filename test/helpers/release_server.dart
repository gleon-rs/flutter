import 'dart:async';
import 'dart:io';

/// A local release mirror: serves [files] (name → bytes), answers [redirects]
/// (name → location), sends redirects whose body never arrives for [stalled],
/// answers [statuses] (name → bare status code) and counts requests per name
/// in [hits].
class ReleaseServer {
  ReleaseServer._(
    this._server, {
    required this.files,
    required this.redirects,
    required this.stalled,
    required this.statuses,
  });

  /// Served files by name; mutable to emulate a changing mirror.
  final Map<String, List<int>> files;

  /// Redirect locations by name.
  final Map<String, String> redirects;

  /// Names whose redirect body stalls.
  final Set<String> stalled;

  /// Names answered with only a status code (no body, no headers).
  final Map<String, int> statuses;

  /// Requests per name.
  final hits = <String, int>{};

  final HttpServer _server;

  StreamSubscription<HttpRequest>? _subscription;

  /// Base URL of the release (with a trailing slash).
  Uri get url => .parse('http://127.0.0.1:${_server.port}/v1.0.0/');

  /// Starts serving on a free loopback port.
  static Future<ReleaseServer> start(
    Map<String, List<int>> files, {
    Map<String, String> redirects = const {},
    Set<String> stalledRedirects = const {},
    Map<String, int> statuses = const {},
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = ReleaseServer._(
      server,
      files: {...files},
      redirects: redirects,
      stalled: stalledRedirects,
      statuses: statuses,
    );
    release._subscription = server.listen(release._handle);

    return release;
  }

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
    response.statusCode = body == null ? HttpStatus.notFound : HttpStatus.ok;
    if (body != null) response.add(body);
    await response.close();
  }
}
