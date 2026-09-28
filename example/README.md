# gleon example

The Flutter counter app, with tests that use `package:gleon/gleon.dart` instead of `flutter_test`:
see `test/counter_test.dart`. The goldens are compared with a loose `ssim` tolerance so that the
macOS-recorded baselines also pass on Linux and Windows (a temporary setting until text-aware
comparison lands; it will move into `.gleon/gleon.yaml`).

```sh
flutter test                   # the build hook fetches the native library on first run
flutter test --update-goldens  # rewrite test/goldens/
flutter run -d macos           # or linux / windows
```
