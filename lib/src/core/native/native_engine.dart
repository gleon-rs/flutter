import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../compare/golden_tolerance.dart';
import '../compare/mask_zone.dart';
import '../config/golden_resolution.dart';
import 'gleon_ffi.dart';
import 'gleon_result.dart';
import 'native_report.dart';

/// The gleon engine behind the native `gleon-ffi` library.
///
/// Calls are synchronous leaf calls (see `gleon_ffi.dart` for why).
abstract final class NativeEngine {
  /// JSON contract version this Dart code understands (`ABI_VERSION` in
  /// `gleon-ffi`). Keep both in lockstep.
  static const expectedAbiVersion = 4;

  /// Asked once per process, on the first call.
  // ignore: avoid-explicit-type-declaration, not obvious from the initializer.
  static final int _abiVersion = GleonFfi.abiVersion();

  /// Compares PNG-encoded [baseline] and [candidate] with [tolerance],
  /// excluding [masks].
  ///
  /// The buffers are read in place by the native code; nothing is copied in.
  /// Throws a [StateError] when the loaded library speaks another ABI.
  static NativeReport compare({
    required Uint8List baseline,
    required Uint8List candidate,
    required GoldenTolerance tolerance,
    List<MaskZone> masks = const [],
  }) {
    _checkAbi();
    final options = utf8.encode(
      jsonEncode({
        if (masks.isNotEmpty)
          'masks': [for (final mask in masks) mask.toNativeJson()],
        'tolerance': tolerance.toNativeJson(),
      }),
    );
    final result = GleonFfi.compare(
      baseline.address,
      baseline.length,
      candidate.address,
      candidate.length,
      options.address,
      options.length,
    );

    return _consume(
      result,
      NativeReport.parse,
      onMissingJson: const NativeError('native result without a report'),
    );
  }

  /// Validates the `.gleon/gleon.yaml` text [yaml] and resolves the rule of
  /// the golden at [path] (relative to the workspace root). [metricsEnv] is
  /// the raw `GLEON_METRICS` value (null when unset).
  static GoldenResolution resolve({
    required String yaml,
    required String path,
    String? metricsEnv,
  }) {
    _checkAbi();
    final yamlBytes = utf8.encode(yaml);
    final pathBytes = utf8.encode(path);
    // `.address` is only allowed as a direct leaf-call argument, hence two
    // calls: a null pointer tells the library the variable is unset.
    final result = switch (metricsEnv) {
      null => GleonFfi.configResolve(
        yamlBytes.address,
        yamlBytes.length,
        pathBytes.address,
        pathBytes.length,
        nullptr,
        0,
      ),
      final env => _resolveWithEnv(yamlBytes, pathBytes, utf8.encode(env)),
    };

    return _consume(
      result,
      (json, _) => GoldenResolution.fromNativeJson(json),
      onMissingJson: const GoldenResolutionError(
        'native result without a response',
      ),
    );
  }

  static Pointer<GleonResult> _resolveWithEnv(
    Uint8List yaml,
    Uint8List path,
    Uint8List env,
  ) => GleonFfi.configResolve(
    yaml.address,
    yaml.length,
    path.address,
    path.length,
    env.address,
    env.length,
  );

  static void _checkAbi() => checkAbiVersion(_abiVersion);

  /// Decodes a UTF-8 JSON [report]; malformed bytes become an error document
  /// that both the compare and the resolve parser read as an error, never as a
  /// pass.
  @visibleForTesting
  // ignore: no-object-declaration, decoded JSON of any shape (parsed after).
  static Object decodeReport(List<int> report) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(report));

      // A JSON `null` is off-contract too: an empty map parses as an error.
      return decoded ?? const <String, Object>{};
    } on FormatException catch (error) {
      final message = 'malformed native report: ${error.message}';

      return {'error': message, 'kind': 'error', 'verdict': 'error'};
    }
  }

  /// Throws a [StateError] unless the loaded library's [abiVersion] is
  /// [expectedAbiVersion].
  @visibleForTesting
  static void checkAbiVersion(int abiVersion) {
    if (abiVersion != expectedAbiVersion) {
      throw StateError(
        'gleon: native library ABI version $abiVersion does not match the '
        'Dart package ($expectedAbiVersion). Rebuild the native library.',
      );
    }
  }

  /// Reads the JSON (and diff PNG) of [result], then frees it.
  static T _consume<T>(
    Pointer<GleonResult> result,
    T Function(Object? json, Uint8List? diff) parse, {
    required T onMissingJson,
  }) {
    try {
      final json = GleonFfi.resultJson(result);
      if (json.ptr == nullptr) return onMissingJson;
      final decoded = decodeReport(json.ptr.asTypedList(json.len));
      final diff = GleonFfi.resultDiffPng(result);

      return parse(
        decoded,
        diff.ptr == nullptr
            ? null
            // Copied out: the slice dies with `result` below.
            : Uint8List.fromList(diff.ptr.asTypedList(diff.len)),
      );
    } finally {
      GleonFfi.resultFree(result);
    }
  }
}
