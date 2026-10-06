import 'package:hooks/hooks.dart' show HookInputUserDefines;

/// The user-defines of the app's `pubspec.yaml` for this package.
abstract interface class UserDefines {
  /// The user-defines the hooks runner passes to the build hook.
  factory UserDefines.of(HookInputUserDefines defines) = _HookUserDefines;

  /// The value of [key], or null.
  // ignore: no-object-declaration, a user-define is any YAML value.
  Object? operator [](String key);

  /// The path [key] holds, resolved against the `pubspec.yaml` that sets it,
  /// or null.
  Uri? path(String key);
}

final class _HookUserDefines implements UserDefines {
  const _HookUserDefines(this._defines);

  final HookInputUserDefines _defines;

  @override
  Object? operator [](String key) => _defines[key];

  @override
  Uri? path(String key) => _defines.path(key);
}
