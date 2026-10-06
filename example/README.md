# gleon example

The Flutter counter app, with tests that use `package:gleon/gleon.dart` instead of `flutter_test`:
see `test/counter_test.dart` (suite-wide setup in `test/flutter_test_config.dart`). The goldens are
recorded on an Apple silicon Mac with the app's real fonts and compared exactly by the rule in
`.gleon/gleon.yaml`, whose `fallback_platform: macos-aarch64` names that platform (see "Real text"
in the package README for how other platforms compare them).

```sh
flutter test                   # the build hook fetches the native library on first run
flutter test --update-goldens  # rewrite this platform's goldens
flutter run -d macos           # or linux / windows
```
