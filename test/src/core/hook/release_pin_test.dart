import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import '../../../helpers/download_cache.dart';
import '../../../helpers/release.dart';
import '../../../helpers/release_server.dart';

// A checkout (a git dependency) pins the gleon commit it was made for; the
// release of its version names the commit its libraries were built from.
// Between releases (`ref: main`) the two may differ: the engine would then not
// be the one the checkout expects, which only an ABI change would show.
void main() {
  const target = Release.target;
  const releasePin = 'aaaa';
  final library = Release.library;
  final fetch = DownloadCache().fetch;
  final pinFile = utf8.encode('$releasePin\n');
  final pinnedSums = utf8.encode(
    '${Release.hash}  ${target.assetName}\n'
    '${sha256.convert(pinFile)}  ${ReleaseDownload.pinFileName}\n',
  );

  Future<ReleaseServer> pinnedRelease() async {
    final server = await ReleaseServer.start({
      ReleaseDownload.checksumsFileName: pinnedSums,
      target.assetName: library,
      ReleaseDownload.pinFileName: pinFile,
    });
    addTearDown(server.close);

    return server;
  }

  test('a release matching the pin of the checkout is used', () async {
    final server = await pinnedRelease();

    final downloaded = await fetch(server.url, pin: releasePin);
    expect(downloaded.readAsBytesSync(), library);
  });

  test('a release of another pin fails, naming both and the tag', () async {
    final server = await pinnedRelease();

    await expectLater(
      fetch(server.url, pin: 'bbbb'),
      throwsDownload(
        allOf(contains('aaaa'), contains('bbbb'), contains('ref: v1.0.0')),
      ),
    );
  });

  test('without a pin (the pub.dev archive) none is asked', () async {
    final server = await pinnedRelease();

    await fetch(server.url);
    expect(server.hits[ReleaseDownload.pinFileName], isNull);
  });

  test('an older release without a pin is not checked', () async {
    final server = await ReleaseServer.start({
      ReleaseDownload.checksumsFileName: utf8.encode(
        '${Release.hash}  ${target.assetName}\n',
      ),
      target.assetName: library,
    });
    addTearDown(server.close);

    final downloaded = await fetch(server.url, pin: 'bbbb');
    expect(downloaded.readAsBytesSync(), library);
  });
}
