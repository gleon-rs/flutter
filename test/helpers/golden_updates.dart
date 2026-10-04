import 'package:flutter_test/flutter_test.dart';

/// Runs [body] with `autoUpdateGoldenFiles` set to [isUpdating] (`true`: as
/// `flutter test --update-goldens` would) and puts the previous value back,
/// so a test behaves the same whatever flags the run was started with.
Future<T> withGoldenUpdates<T>(
  Future<T> Function() body, {
  bool isUpdating = true,
}) async {
  // ignore: avoid-unnecessary-local-variable, restored after the body.
  final wasUpdating = autoUpdateGoldenFiles;
  autoUpdateGoldenFiles = isUpdating;
  try {
    return await body();
  } finally {
    autoUpdateGoldenFiles = wasUpdating;
  }
}
