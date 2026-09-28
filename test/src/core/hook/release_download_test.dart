import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/native_download_exception.dart';
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

  Future<File> fetch(Uri releaseUrl, {Duration? redirectTimeout}) =>
      ReleaseDownload.fetchLibrary(
        releaseUrl: releaseUrl,
        target: target,
        cacheDir: cache ?? .systemTemp,
        redirectTimeout: redirectTimeout ?? const .new(seconds: 30),
      );

  Matcher throwsDownload(Object message) => throwsA(
    isA<NativeDownloadException>().having(
      (error) => error.message,
      'message',
      message,
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
  });

  test('a missing release explains how to proceed', () async {
    final server = await ReleaseServer.start(const {});
    addTearDown(server.close);

    await expectLater(
      fetch(server.url),
      throwsDownload(
        allOf(contains('HTTP 404'), contains('ffi_path'), contains('ref')),
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

  test('download errors name the package', () {
    expect('${const NativeDownloadException('boom')}', 'gleon: boom');
  });
}
