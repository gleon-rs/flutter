import 'package:hooks/hooks.dart' show HookInputUserDefines;

import 'user_defines.dart';

/// The [UserDefines] the hooks runner passes to the build hook
/// (`hook/build.dart`, the only user of this adapter).
final class HookUserDefines implements UserDefines {
  /// Reads [_defines].
  const HookUserDefines(this._defines);

  final HookInputUserDefines _defines;

  @override
  Object? operator [](String key) => _defines[key];

  @override
  Uri? path(String key) => _defines.path(key);
}
