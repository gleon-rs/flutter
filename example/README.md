# gleon example

The Flutter counter app, with tests that use `package:gleon/gleon.dart` instead of `flutter_test`:
see `test/counter_test.dart` (suite-wide setup in `test/flutter_test_config.dart`). The goldens are
recorded on an Apple silicon Mac with the app's real fonts and compared exactly by the rule in
`.gleon/gleon.yaml`. Its `fallback_platform: macos-aarch64` names that platform: there the text is
compared too; Linux and Windows compare everything else exactly and ignore the text, until they
record their own goldens in `test/goldens/<os>-<arch>/`.

```sh
flutter test                   # the build hook fetches the native library on first run
flutter test --update-goldens  # rewrite this platform's goldens
flutter run -d macos           # or linux / windows
```
