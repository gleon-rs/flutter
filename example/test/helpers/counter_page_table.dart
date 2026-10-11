import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:gleon_example/counter_page.dart';

/// The counter page as alchemist users lay out their goldens: a table of
/// scenarios, here at the default text size and enlarged. Shared by the
/// golden test and the benchmark, so both render the same image.
class CounterPageTable extends StatelessWidget {
  /// Creates the table.
  const CounterPageTable({super.key});

  @override
  Widget build(BuildContext context) => GoldenTestGroup(
    children: [
      GoldenTestScenario(name: 'default', child: _phone),
      GoldenTestScenario.withTextScaleFactor(
        name: 'large text',
        textScaler: const .linear(1.5),
        child: _phone,
      ),
    ],
  );
}

/// The page at a small phone's size (a `Scaffold` needs bounds).
const _phone = SizedBox(width: 240, height: 320, child: CounterPage());
