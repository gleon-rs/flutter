# gleon example

The Flutter counter app, with tests that use `package:gleon/gleon.dart` instead of `flutter_test`:
see `test/counter_test.dart` (suite-wide setup in `test/flutter_test_config.dart`). The goldens are
compared with the loose `ssim` tolerance of the rule in `.gleon/gleon.yaml`, so that the
macOS-recorded baselines also pass on Linux and Windows (temporary, until text-aware comparison
lands).

```sh
flutter test                   # the build hook fetches the native library on first run
flutter test --update-goldens  # rewrite test/goldens/
flutter run -d macos           # or linux / windows
```
