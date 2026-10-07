/// The user-defines of the app's `pubspec.yaml` for this package.
///
/// Free of `package:hooks`, so `NativeLibrary` is tested with plain maps;
/// the build hook passes `HookUserDefines`.
abstract interface class UserDefines {
  /// The value of [key], or null.
  // ignore: no-object-declaration, a user-define is any YAML value.
  Object? operator [](String key);

  /// The path [key] holds, resolved against the `pubspec.yaml` that sets it,
  /// or null (also for a value that is not a string).
  Uri? path(String key);
}
