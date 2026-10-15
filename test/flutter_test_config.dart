import 'dart:async';

import 'package:gleon/src/core/config/gleon_session.dart';
import 'package:gleon/src/flutter/flutter_session.dart';

/// This package's tests run in an environment of their own: the `GLEON_*`
/// variables of the shell (metrics, a run id) never apply to the process
/// session, and tests that need them pass a session with its environment.
// ignore: prefer-async-callback, the signature flutter_test looks for.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FlutterSession.debugEnvironment = const GleonEnvironment();
  await testMain();
}
