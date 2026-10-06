import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [body] with `debugPrint` captured (reset to the test binding's
/// override before the test ends, as the binding requires) and returns the
/// printed lines.
Future<List<String>> capturePrints(AsyncCallback body) async {
  final lines = <String>[];
  debugPrint = (message, {wrapWidth}) => lines.add(message ?? '(null)');
  try {
    await body();
  } finally {
    debugPrint = TestWidgetsFlutterBinding.instance.debugPrintOverride;
  }

  return lines;
}
