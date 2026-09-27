import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/hook/download.dart';
import 'package:gleon/src/hook/targets.dart';

/// Serves [files] (path → bytes), answers [redirects] (path → location),
/// sends redirects whose body never arrives for [stalledRedirects] and counts
/// requests per path.
class _ReleaseServer {
  _ReleaseServer._(this._server, this.files, this.redirects, this.stalled);

  static Future<_ReleaseServer> start(
    Map<String, List<int>> files, {
    Map<String, String> redirects = const {},
    Set<String> stalledRedirects = const {},
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = _ReleaseServer._(
      server,
      files,
      redirects,
      stalledRedirects,
    );
    server.listen((request) {
      final name = request.uri.pathSegments.last;
      release.hits[name] = (release.hits[name] ?? 0) + 1;
      if (release.stalled.contains(name)) {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, 'elsewhere')
          ..contentLength = 1024
          ..add([0]);
        request.response.flush().ignore();
        return;
      }
      if (release.redirects[name] case final location?) {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, location)
          ..close();
        return;
      }
      final body = release.files[name];
      request.response.statusCode = body == null
          ? HttpStatus.notFound
          : HttpStatus.ok;
      if (body != null) request.response.add(body);
      request.response.close();
    });
    return release;
  }

  final HttpServer _server;
  final Map<String, List<int>> files;
  final Map<String, String> redirects;
  final Set<String> stalled;
  final hits = <String, int>{};

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/v1.0.0/');

  Future<void> close() => _server.close(force: true);
}

void main() {
  const target = NativeTarget.linuxX64;
  final library = List<int>.generate(4096, (i) => i % 251);
  final hash = sha256.convert(library).toString();

  late Directory cache;
  setUp(() => cache = Directory.systemTemp.createTempSync('gleon_hook_'));
  tearDown(() => cache.deleteSync(recursive: true));

  Future<_ReleaseServer> serve({List<int>? asset, String? sums}) =>
      _ReleaseServer.start({
        checksumsFileName: (sums ?? '$hash  ${target.assetName}\n').codeUnits,
        target.assetName: ?asset,
      });

  test('downloads, verifies and then reuses the cached library', () async {
    final server = await serve(asset: library);
    addTearDown(server.close);

    final first = await fetchReleaseLibrary(
      releaseUrl: server.url,
      target: target,
      cacheDir: cache,
    );
    expect(first.readAsBytesSync(), library);
    expect(
      first.path,
      endsWith('$hash${Platform.pathSeparator}libgleon_ffi.so'),
    );

    final second = await fetchReleaseLibrary(
      releaseUrl: server.url,
      target: target,
      cacheDir: cache,
    );
    expect(second.path, first.path);
    expect(server.hits, {checksumsFileName: 1, target.assetName: 1});
  });

  test('never keeps a library whose checksum does not match', () async {
    final server = await serve(asset: [...library, 0]);
    addTearDown(server.close);

    await expectLater(
      fetchReleaseLibrary(
        releaseUrl: server.url,
        target: target,
        cacheDir: cache,
      ),
      throwsA(
        isA<NativeDownloadException>().having(
          (e) => e.message,
          'message',
          contains('checksum mismatch'),
        ),
      ),
    );
    expect(
      cache.listSync(recursive: true).whereType<File>().map((f) => f.path),
      everyElement(isNot(endsWith('.so'))),
    );
  });

  test('a missing release explains how to proceed', () async {
    final server = await _ReleaseServer.start({});
    addTearDown(server.close);

    await expectLater(
      fetchReleaseLibrary(
        releaseUrl: server.url,
        target: target,
        cacheDir: cache,
      ),
      throwsA(
        isA<NativeDownloadException>().having(
          (e) => e.message,
          'message',
          allOf(contains('HTTP 404'), contains('ffi_path'), contains('ref')),
        ),
      ),
    );
  });

  test('a release without this target names the missing asset', () async {
    final server = await serve(sums: '$hash  other.dll\n');
    addTearDown(server.close);

    await expectLater(
      fetchReleaseLibrary(
        releaseUrl: server.url,
        target: target,
        cacheDir: cache,
      ),
      throwsA(
        isA<NativeDownloadException>().having(
          (e) => e.message,
          'message',
          contains(target.assetName),
        ),
      ),
    );
  });

  test('parses sha256sum output and pubspec versions', () {
    expect(parseChecksums('${'A' * 64}  a.so\n${'b' * 64} *b.dll\ngarbage\n'), {
      'a.so': 'a' * 64,
      'b.dll': 'b' * 64,
    });
    expect(
      readPubspecVersion('name: x\nversion: 1.2.3-dev.1 # c\n'),
      '1.2.3-dev.1',
    );
    expect(readPubspecVersion("version: '0.0.1'"), '0.0.1');
    expect(readPubspecVersion('name: x'), isNull);
  });

  test('only https, or plain http to localhost, is accepted', () async {
    for (final url in ['file:///mirror/v1.0.0/', 'http://mirror.example/v1/']) {
      await expectLater(
        fetchReleaseLibrary(
          releaseUrl: Uri.parse(url),
          target: target,
          cacheDir: cache,
        ),
        throwsA(
          isA<NativeDownloadException>().having(
            (e) => e.message,
            'message',
            allOf(contains('https'), contains('ffi_path')),
          ),
        ),
        reason: url,
      );
    }
  });

  test('refuses a redirect to plain http', () async {
    final server = await _ReleaseServer.start(
      {checksumsFileName: '$hash  ${target.assetName}\n'.codeUnits},
      redirects: {target.assetName: 'http://mirror.example/lib.so'},
    );
    addTearDown(server.close);

    await expectLater(
      fetchReleaseLibrary(
        releaseUrl: server.url,
        target: target,
        cacheDir: cache,
      ),
      throwsA(
        isA<NativeDownloadException>().having(
          (e) => e.message,
          'message',
          contains('insecure'),
        ),
      ),
    );
  });

  test('a redirect whose body stalls fails instead of hanging', () async {
    final server = await _ReleaseServer.start(
      {checksumsFileName: '$hash  ${target.assetName}\n'.codeUnits},
      stalledRedirects: {target.assetName},
    );
    addTearDown(server.close);

    await expectLater(
      fetchReleaseLibrary(
        releaseUrl: server.url,
        target: target,
        cacheDir: cache,
        redirectTimeout: const Duration(milliseconds: 100),
      ),
      throwsA(
        isA<NativeDownloadException>().having(
          (e) => e.message,
          'message',
          contains('TimeoutException'),
        ),
      ),
    );
    // Every attempt timed out and was retried.
    expect(server.hits[target.assetName], 3);
  });

  test('follows allowed redirects', () async {
    final server = await _ReleaseServer.start(
      {
        checksumsFileName: '$hash  ${target.assetName}\n'.codeUnits,
        'stored.so': library,
      },
      redirects: {target.assetName: 'stored.so'},
    );
    addTearDown(server.close);

    final file = await fetchReleaseLibrary(
      releaseUrl: server.url,
      target: target,
      cacheDir: cache,
    );
    expect(file.readAsBytesSync(), library);
    expect(server.hits['stored.so'], 1);
  });

  test('windows builds link the C runtime statically in every setup', () {
    const flag = '-C target-feature=+crt-static';
    final windows = NativeTarget.windowsX64;
    expect(windows.cargoEnvironment({}), {
      'CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS': flag,
    });
    // Cargo ignores per-target flags when RUSTFLAGS is set: append instead.
    expect(windows.cargoEnvironment({'RUSTFLAGS': '-D warnings'}), {
      'RUSTFLAGS': '-D warnings $flag',
    });
    expect(
      windows.cargoEnvironment({'CARGO_ENCODED_RUSTFLAGS': '-Dwarnings'}),
      {
        'CARGO_ENCODED_RUSTFLAGS':
            '-Dwarnings\x1f-C\x1ftarget-feature=+crt-static',
      },
    );
    expect(NativeTarget.linuxX64.cargoEnvironment({'RUSTFLAGS': 'x'}), isEmpty);
  });

  test('target keys match code_assets and dart:ffi naming', () {
    expect(NativeTarget.byKey('macos-arm64'), NativeTarget.macosArm64);
    expect(NativeTarget.byKey('windows-x64'), NativeTarget.windowsX64);
    expect(NativeTarget.byKey('macos-x64'), isNull);
  });

  test('release asset names are unique per target', () {
    final names = NativeTarget.values.map((t) => t.assetName).toSet();
    expect(names, hasLength(NativeTarget.values.length));
    expect(NativeTarget.windowsX64.assetName, 'gleon_ffi-windows-x64.dll');
  });
}
