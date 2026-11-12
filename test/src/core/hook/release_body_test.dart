import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import '../../../helpers/download_cache.dart';
import '../../../helpers/release.dart';
import '../../../helpers/release_server.dart';

// The bodies of a release download: a server that stalls, one that is slow,
// and one that sends more than any library.
void main() {
  const target = Release.target;
  final library = Release.library;
  final sums = Release.sums;
  final fetch = DownloadCache().fetch;

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

  // A size the server announces is refused before the body is read: here it
  // would never arrive.
  test('an announced body beyond any library is refused unread', () async {
    final server = await ReleaseServer.start(
      {ReleaseDownload.checksumsFileName: sums},
      stalledFiles: {target.assetName},
    );
    addTearDown(server.close);

    await expectLater(
      fetch(server.url, bodyTimeout: const .new(seconds: 2), maxBytes: 512),
      throwsDownload(contains('more than 512 bytes')),
    );
    expect(server.hits[target.assetName], 1);
  });
}
