import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/network_failure.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import '../../../helpers/download_cache.dart';
import '../../../helpers/release.dart';
import '../../../helpers/release_server.dart';

void main() {
  const target = Release.target;
  final library = Release.library;
  final hash = Release.hash;
  final sums = Release.sums;
  final cache = DownloadCache();
  final fetch = cache.fetch;

  test('downloads, verifies and then reuses the cached library', () async {
    final server = await ReleaseServer.start({
      ReleaseDownload.checksumsFileName: sums,
      target.assetName: library,
    });
    addTearDown(server.close);

    final first = await fetch(server.url);
    expect(first.readAsBytesSync(), library);
    expect(
      first.path,
      endsWith('$hash${Platform.pathSeparator}libgleon_ffi.so'),
    );

    final second = await fetch(server.url);
    expect(second.path, first.path);
    expect(server.hits, {
      ReleaseDownload.checksumsFileName: 1,
      target.assetName: 1,
    });
  });

  test('never keeps a library whose checksum does not match', () async {
    final server = await ReleaseServer.start({
      ReleaseDownload.checksumsFileName: sums,
      target.assetName: library.followedBy(const [0]).toList(),
    });
    addTearDown(server.close);

    await expectLater(
      fetch(server.url),
      throwsDownload(contains('checksum mismatch')),
    );
    final files = cache.dir.listSync(recursive: true).whereType<File>();
    expect(
      files.map((file) => file.path),
      everyElement(isNot(endsWith('.so'))),
    );
    // A list just downloaded is not asked for again.
    expect(server.hits[ReleaseDownload.checksumsFileName], 1);
  });

  test('a missing release explains how to proceed', () async {
    final server = await ReleaseServer.start(const {});
    addTearDown(server.close);

    await expectLater(
      fetch(server.url),
      throwsDownload(
        allOf(
          contains('HTTP 404'),
          contains('`release_url` user-define (${server.url})'),
          contains('gleon 1.0.0'),
          contains('ffi_path'),
        ),
      ),
    );
  });

  test('a release without this target names the missing asset', () async {
    final server = await ReleaseServer.start({
      ReleaseDownload.checksumsFileName: '$hash  other.dll\n'.codeUnits,
    });
    addTearDown(server.close);

    await expectLater(
      fetch(server.url),
      throwsDownload(contains(target.assetName)),
    );
  });

  test('a stale cached checksum list is refreshed once', () async {
    final mirror = await ReleaseServer.start({
      ReleaseDownload.checksumsFileName: '$hash  other.dll\n'.codeUnits,
    });
    addTearDown(mirror.close);
    final ReleaseServer(:files, :hits, :url) = mirror;
    await expectLater(fetch(url), throwsDownload(isNotEmpty));

    // Same URL (a mutable mirror), now with the asset.
    files
      ..[ReleaseDownload.checksumsFileName] = sums
      ..[target.assetName] = library;
    final downloaded = await fetch(url);

    expect(downloaded.readAsBytesSync(), library);
    expect(hits[ReleaseDownload.checksumsFileName], 2);
  });

  group('a mirror kept across upgrades', () {
    final upgraded = List<int>.generate(4096, (i) => i % 241);
    final upgradedHash = sha256.convert(upgraded).toString();
    final upgradedSums = '$upgradedHash  ${target.assetName}\n'.codeUnits;

    Future<ReleaseServer> mirror() async {
      final server = await ReleaseServer.start({
        ReleaseDownload.checksumsFileName: sums,
        target.assetName: library,
      });
      addTearDown(server.close);
      final downloaded = await fetch(server.url);
      expect(downloaded.readAsBytesSync(), library);

      return server;
    }

    test('serves the release of the new version', () async {
      final ReleaseServer(:files, :hits, :url) = await mirror();
      files
        ..[ReleaseDownload.checksumsFileName] = upgradedSums
        ..[target.assetName] = upgraded;

      final downloaded = await fetch(url, packageVersion: '1.1.0');
      expect(downloaded.readAsBytesSync(), upgraded);
      expect(hits[ReleaseDownload.checksumsFileName], 2);
    });

    test('reloads a cached list that disagrees with the library', () async {
      final ReleaseServer(:files, :hits, :url) = await mirror();
      // The cached library is gone, and the mirror changed in place.
      Directory('${cache.dir.path}/$hash').deleteSync(recursive: true);
      files
        ..[ReleaseDownload.checksumsFileName] = upgradedSums
        ..[target.assetName] = upgraded;

      final downloaded = await fetch(url);
      expect(downloaded.readAsBytesSync(), upgraded);
      expect(hits[ReleaseDownload.checksumsFileName], 2);
    });

    test('names release_url when the library still disagrees', () async {
      final ReleaseServer(:files, :hits, :url) = await mirror();
      Directory('${cache.dir.path}/$hash').deleteSync(recursive: true);
      files[target.assetName] = upgraded;

      await expectLater(
        fetch(url),
        throwsDownload(
          allOf(
            contains('checksum mismatch'),
            contains(ReleaseDownload.checksumsFileName),
            contains('`release_url`'),
          ),
        ),
      );
      expect(hits[ReleaseDownload.checksumsFileName], 2);
    });
  });

  test('parses sha256sum output and pubspec versions', () {
    expect(
      ReleaseDownload.parseChecksums(
        '${'A' * 64}  a.so\n${'b' * 64} *b.dll\ngarbage\n',
      ),
      {'a.so': 'a' * 64, 'b.dll': 'b' * 64},
    );
    expect(
      ReleaseDownload.readPubspecVersion('name: x\nversion: 1.2.3-dev.1 # c\n'),
      '1.2.3-dev.1',
    );
    expect(ReleaseDownload.readPubspecVersion("version: '0.0.1'"), '0.0.1');
    expect(ReleaseDownload.readPubspecVersion('name: x'), isNull);
  });

  test("the default release URL points at this repository's tag", () {
    expect(
      ReleaseDownload.defaultUrl('1.2.3').toString(),
      'https://github.com/gleon-rs/flutter/releases/download/v1.2.3/',
    );
  });

  // This machine is all of 127.0.0.0/8 (Debian names itself 127.0.1.1),
  // `localhost` and ::1; plain http anywhere else would let a network swap
  // the libraries and their checksum list alike.
  test('plain http reaches this machine only', () {
    for (final (url, isThisMachine) in [
      ('http://localhost:8080/', true),
      ('http://127.0.0.1/', true),
      ('http://127.0.1.1:8080/', true),
      ('http://127.255.0.2/', true),
      ('http://[::1]:8080/', true),
      ('http://128.0.0.1/', false),
      ('http://127.0.0.1.example/', false),
      ('http://localhost.example/', false),
      ('http://mirror.example/', false),
    ]) {
      expect(
        ReleaseDownload.isThisMachine(.parse(url)),
        isThisMachine,
        reason: url,
      );
    }
  });

  test('only https, or plain http to localhost, is accepted', () async {
    for (final url in ['file:///mirror/v1.0.0/', 'http://mirror.example/v1/']) {
      await expectLater(
        fetch(Uri.parse(url)),
        throwsDownload(allOf(contains('https'), contains('ffi_path'))),
        reason: url,
      );
    }
  });

  test('refuses a redirect to plain http', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums},
      redirects: {target.assetName: 'http://mirror.example/lib.so'},
    );
    addTearDown(server.close);

    await expectLater(fetch(server.url), throwsDownload(contains('insecure')));
  });

  test('a redirect whose body stalls fails instead of hanging', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums},
      stalledRedirects: {target.assetName},
    );
    addTearDown(server.close);

    await expectLater(
      fetch(server.url, redirectTimeout: const Duration(milliseconds: 100)),
      throwsDownload(contains('TimeoutException')),
    );
    // Every attempt timed out and was retried.
    expect(server.hits[target.assetName], 3);
  });

  test('a file whose body stalls fails instead of hanging', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums},
      stalledFiles: {target.assetName},
    );
    addTearDown(server.close);

    await expectLater(
      fetch(server.url, bodyTimeout: const Duration(milliseconds: 100)),
      throwsDownload(contains('TimeoutException')),
    );
    // Every attempt timed out on a fresh connection and was retried.
    expect(server.hits[target.assetName], 3);
  });

  // The body timeout is one of silence, not of the whole download: a slow
  // but steady connection gets the library, a stalled one is given up.
  test('a slow but steady body arrives', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums, target.assetName: library},
      dripped: {target.assetName: const .new(milliseconds: 150)},
    );
    addTearDown(server.close);

    final downloaded = await fetch(
      server.url,
      bodyTimeout: const .new(milliseconds: 400),
    );
    expect(downloaded.readAsBytesSync(), library);
    expect(server.hits[target.assetName], 1);
  });

  // Announced by its Content-Length, or streamed without one.
  test('a body beyond any library is refused at once', () async {
    final files = {
      ReleaseDownload.checksumsFileName: sums,
      target.assetName: library,
    };
    for (final dripped in <Map<String, Duration>>[
      const {},
      {target.assetName: .zero},
    ]) {
      final server = await ReleaseServer.start(files, dripped: dripped);
      addTearDown(server.close);

      await expectLater(
        fetch(server.url, maxBytes: 1024),
        throwsDownload(contains('more than 1024 bytes')),
      );
      expect(server.hits[target.assetName], 1, reason: '$dripped');
    }
  });

  test('follows allowed redirects', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums, 'stored.so': library},
      redirects: {target.assetName: 'stored.so'},
    );
    addTearDown(server.close);

    final downloaded = await fetch(server.url);
    expect(downloaded.readAsBytesSync(), library);
    expect(server.hits['stored.so'], 1);
  });

  test('follows a redirect to another host', () async {
    // GitHub redirects release assets to its storage host.
    final storage = await ReleaseServer.start({'stored.so': library});
    addTearDown(storage.close);
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums},
      redirects: {target.assetName: '${storage.url.resolve('stored.so')}'},
    );
    addTearDown(server.close);

    final downloaded = await fetch(server.url);
    expect(downloaded.readAsBytesSync(), library);
    expect(storage.hits, {'stored.so': 1});
  });

  test('concurrent builds share one verified library', () async {
    final server = await ReleaseServer.start({
      ReleaseDownload.checksumsFileName: sums,
      target.assetName: library,
    });
    addTearDown(server.close);

    final downloaded = await Future.wait([
      fetch(server.url),
      fetch(server.url),
    ]);
    expect({for (final file in downloaded) file.path}, hasLength(1));
    expect(downloaded.firstOrNull?.readAsBytesSync(), library);
    final leftovers = cache.dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.tmp'));
    expect(leftovers, isEmpty);
  });

  test('a checksum list without checksums is rejected', () async {
    final server = await ReleaseServer.start({
      ReleaseDownload.checksumsFileName: 'not a list'.codeUnits,
    });
    addTearDown(server.close);

    await expectLater(
      fetch(server.url),
      throwsDownload(contains('is not a valid checksum list')),
    );
  });

  test('a client error fails at once, without retrying', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums},
      statuses: {target.assetName: HttpStatus.forbidden},
    );
    addTearDown(server.close);

    await expectLater(
      fetch(server.url),
      throwsDownload(contains('failed with HTTP 403')),
    );
    expect(server.hits[target.assetName], 1);
  });

  // Each takes the backoff of every attempt (1 s, then 2 s).
  for (final status in [
    HttpStatus.tooManyRequests,
    HttpStatus.serviceUnavailable,
  ]) {
    test(
      'HTTP $status is retried, then reported as a network failure',
      () async {
        final server = await ReleaseServer.start(
          {ReleaseDownload.checksumsFileName: sums},
          statuses: {target.assetName: status},
        );
        addTearDown(server.close);

        await expectLater(
          fetch(server.url),
          throwsA(
            isA<NetworkFailure>().having(
              (error) => error.message,
              'message',
              allOf(startsWith('gleon: '), contains('HTTP $status')),
            ),
          ),
        );
        expect(server.hits[target.assetName], 3);
      },
    );
  }

  test('the credentials of a mirror never appear in a message', () async {
    final server = await ReleaseServer.start(const {});
    addTearDown(server.close);
    final url = server.url.replace(userInfo: 'user:s3cret');

    await expectLater(
      fetch(url),
      throwsDownload(allOf(contains('HTTP 404'), isNot(contains('s3cret')))),
    );
  });

  // Any URL of a message loses its user and password, the mirror's and
  // those of a redirect alike.
  test('no credentials of any URL appear in a message', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums},
      redirects: {target.assetName: 'http://cdn:t%40ken@mirror.example/lib.so'},
    );
    addTearDown(server.close);

    await expectLater(
      fetch(server.url.replace(userInfo: 'user:s3cret')),
      throwsDownload(
        allOf(
          contains('insecure'),
          contains('http://mirror.example/lib.so'),
          isNot(contains('t%40ken')),
          isNot(contains('s3cret')),
        ),
      ),
    );
  });

  test('the loopback address is reached without the proxy', () {
    const environment = {
      'http_proxy': 'proxy:3128',
      'https_proxy': 'proxy:3128',
    };
    for (final host in ['localhost', '127.0.0.1', '[::1]']) {
      expect(
        ReleaseDownload.proxyFor(.parse('http://$host:8080/'), environment),
        'DIRECT',
        reason: host,
      );
    }
    expect(
      ReleaseDownload.proxyFor(.parse('https://github.com/'), environment),
      'PROXY proxy:3128',
    );
  });

  test('a redirect without a location fails', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums},
      statuses: {target.assetName: HttpStatus.found},
    );
    addTearDown(server.close);

    await expectLater(
      fetch(server.url),
      throwsDownload(contains('redirect without a location')),
    );
  });

  test('a redirect loop stops after five redirects', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums},
      redirects: {target.assetName: target.assetName},
    );
    addTearDown(server.close);

    await expectLater(
      fetch(server.url),
      throwsDownload(contains('more than 5 redirects')),
    );
    expect(server.hits[target.assetName], 6);
  });
}
