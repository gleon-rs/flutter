# gleon example

The Flutter counter app, with tests that use `package:gleon/gleon.dart` instead of `flutter_test`:
see `test/counter_test.dart` and the suite-wide defaults in `test/flutter_test_config.dart`
(`GoldenMode.ssim`).

```sh
flutter test                   # the build hook fetches the native library on first run
flutter test --update-goldens  # rewrite test/goldens/
flutter run -d macos           # or linux / windows
```
