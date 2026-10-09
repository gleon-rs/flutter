import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_target.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import '../../../helpers/release_server.dart';

void main() {
  const target = NativeTarget.linuxX64;
  final library = List<int>.generate(4096, (i) => i % 251);
  final hash = sha256.convert(library).toString();
  final sums = '$hash  ${target.assetName}\n'.codeUnits;

  Directory? cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('gleon_hook_'));
  tearDown(() => cache?.deleteSync(recursive: true));

  Future<File> fetch(
    Uri releaseUrl, {
    String packageVersion = '1.0.0',
    Duration redirectTimeout = const .new(seconds: 30),
    Duration bodyTimeout = const .new(minutes: 3),
  }) => ReleaseDownload.fetchLibrary(
    releaseUrl: releaseUrl,
    packageVersion: packageVersion,
    target: target,
    cacheDir: cache ?? .systemTemp,
    redirectTimeout: redirectTimeout,
    bodyTimeout: bodyTimeout,
  );

  // Hook errors are printed verbatim: every one names gleon first.
  Matcher throwsDownload(Object message) => throwsA(
    isA<StateError>().having(
      (error) => error.message,
      'message',
      allOf(startsWith('gleon: '), message),
    ),
  );

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
    final files = cache?.listSync(recursive: true).whereType<File>();
    expect(
      files?.map((file) => file.path),
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
    final fetched = await fetch(url);

    expect(fetched.readAsBytesSync(), library);
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
      final fetched = await fetch(server.url);
      expect(fetched.readAsBytesSync(), library);

      return server;
    }

    test('serves the release of the new version', () async {
      final ReleaseServer(:files, :hits, :url) = await mirror();
      files
        ..[ReleaseDownload.checksumsFileName] = upgradedSums
        ..[target.assetName] = upgraded;

      final fetched = await fetch(url, packageVersion: '1.1.0');
      expect(fetched.readAsBytesSync(), upgraded);
      expect(hits[ReleaseDownload.checksumsFileName], 2);
    });

    test('reloads a cached list that disagrees with the library', () async {
      final ReleaseServer(:files, :hits, :url) = await mirror();
      // The cached library is gone, and the mirror changed in place.
      Directory('${(cache ?? fail('no cache')).path}/$hash')
          .deleteSync(recursive: true);
      files
        ..[ReleaseDownload.checksumsFileName] = upgradedSums
        ..[target.assetName] = upgraded;

      final fetched = await fetch(url);
      expect(fetched.readAsBytesSync(), upgraded);
      expect(hits[ReleaseDownload.checksumsFileName], 2);
    });

    test('names release_url when the library still disagrees', () async {
      final ReleaseServer(:files, :hits, :url) = await mirror();
      Directory('${(cache ?? fail('no cache')).path}/$hash')
          .deleteSync(recursive: true);
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

  test('follows allowed redirects', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums, 'stored.so': library},
      redirects: {target.assetName: 'stored.so'},
    );
    addTearDown(server.close);

    final fetched = await fetch(server.url);
    expect(fetched.readAsBytesSync(), library);
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

    final fetched = await fetch(server.url);
    expect(fetched.readAsBytesSync(), library);
    expect(storage.hits, {'stored.so': 1});
  });

  test('concurrent builds share one verified library', () async {
    final server = await ReleaseServer.start({
      ReleaseDownload.checksumsFileName: sums,
      target.assetName: library,
    });
    addTearDown(server.close);

    final fetched = await Future.wait([fetch(server.url), fetch(server.url)]);
    expect({for (final file in fetched) file.path}, hasLength(1));
    expect(fetched.firstOrNull?.readAsBytesSync(), library);
    final leftovers = cache
        ?.listSync(recursive: true)
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
