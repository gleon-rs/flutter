import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../bin/src/release_server.dart';

void main() {
  const asset = 'libgleon_ffi-macos-arm64.dylib';

  /// A release serving one [asset] of `content`, closed with the test.
  Future<ReleaseServer> serve(String content) async {
    final dir = Directory.systemTemp.createTempSync('gleon_release_server_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/$asset')..writeAsStringSync(content);
    final server = await ReleaseServer.start({asset: file});
    addTearDown(server.close);

    return server;
  }

  test('serves the assets and their checksum list like a release', () async {
    final server = await serve('not a library');
    expect(server.url.scheme, 'http');
    expect(server.url.host, '127.0.0.1');
    expect(server.url.path, '/');

    final (status, checksums) = await _get(
      server,
      ReleaseServer.checksumsFileName,
    );
    expect(status, HttpStatus.ok);
    expect(
      checksums,
      ReleaseServer.checksumsOf({asset: utf8.encode('not a library')}),
    );
    expect(checksums, matches(RegExp('^[0-9a-f]{64}  $asset\n\$')));

    final (assetStatus, bytes) = await _get(server, asset);
    expect(assetStatus, HttpStatus.ok);
    expect(bytes, 'not a library');

    final (missing, _) = await _get(server, 'libgleon_ffi-linux-x64.so');
    expect(missing, HttpStatus.notFound);
    expect(server.requests, [
      ReleaseServer.checksumsFileName,
      asset,
      'libgleon_ffi-linux-x64.so',
    ]);
  });

  test('the checksum list is sorted by name', () {
    final list = ReleaseServer.checksumsOf({
      for (final name in ['b.so', 'a.dylib']) name: [1],
    });
    final names = [
      for (final line in const LineSplitter().convert(list))
        RegExp(r'^[0-9a-f]{64}  (.*)$').firstMatch(line)?.group(1),
    ];
    expect(names, ['a.dylib', 'b.so']);
  });
}

/// GETs [name] from [server]: the status and the body.
Future<(int, String)> _get(ReleaseServer server, String name) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(server.url.resolve(name));
    final response = await request.close();

    return (response.statusCode, await utf8.decodeStream(response));
  } finally {
    client.close(force: true);
  }
}
