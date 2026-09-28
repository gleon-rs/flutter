import 'package:flutter/material.dart';

/// A page that counts button presses.
class CounterPage extends StatefulWidget {
  /// Creates the page.
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  static const _goal = 10;

  int _counter = 0;

  void _handleIncrement() => setState(() => _counter += 1);

  @override
  Widget build(BuildContext context) {
    final ThemeData(:colorScheme, :textTheme) = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: const Text('gleon counter')),
        backgroundColor: colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              key: const ValueKey('counter'),
              style: textTheme.headlineMedium,
            ),
            // Visible progress towards the goal. Flutter's test font draws
            // every glyph as the same box, so goldens could not see digits.
            Padding(
              padding: const .all(32),
              child: LinearProgressIndicator(
                value: (_counter / _goal).clamp(0, 1),
                minHeight: 8,
                semanticsLabel: 'Progress towards $_goal presses',
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('increment'),
        tooltip: 'Increment',
        heroTag: 'increment',
        onPressed: _handleIncrement,
        child: const Icon(Icons.add, semanticLabel: 'Increment'),
      ),
    );
  }
}
