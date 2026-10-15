import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/core/hook/release_download.dart';

import 'release.dart';

/// A fresh download cache for every test of the suite that creates it (in
/// `main`, outside any test).
final class DownloadCache {
  DownloadCache() {
    setUp(() => _dir = Directory.systemTemp.createTempSync('gleon_hook_'));
    tearDown(() => _dir?.deleteSync(recursive: true));
  }

  Directory? _dir;

  /// The cache of the current test.
  Directory get dir => _dir ?? fail('no download cache outside a test');

  /// Downloads the library of [Release.target] from [releaseUrl] into [dir].
  Future<File> fetch(
    Uri releaseUrl, {
    String packageVersion = '1.0.0',
    String? pin,
    Duration redirectTimeout = const .new(seconds: 30),
    Duration bodyTimeout = const .new(minutes: 1),
    int maxBytes = 64 << 20,
  }) => ReleaseDownload.fetchLibrary(
    releaseUrl: releaseUrl,
    packageVersion: packageVersion,
    target: Release.target,
    cacheDir: dir,
    pin: pin,
    redirectTimeout: redirectTimeout,
    bodyTimeout: bodyTimeout,
    maxBytes: maxBytes,
  );
}
