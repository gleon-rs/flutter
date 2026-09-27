import 'package:flutter/material.dart';

void main() => runApp(const CounterApp());

/// The classic Flutter counter, used to demonstrate gleon golden tests.
class CounterApp extends StatelessWidget {
  /// Creates the app.
  const CounterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'gleon counter',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const CounterPage(),
  );
}

/// A page that counts button presses.
class CounterPage extends StatefulWidget {
  /// Creates the page.
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      title: const Text('gleon counter'),
    ),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('You have pushed the button this many times:'),
          Text(
            '$_counter',
            key: const ValueKey('counter'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          // Visible progress towards 10 presses. Flutter's test font draws
          // every glyph as the same box, so goldens could not see the digits.
          Padding(
            padding: const EdgeInsets.all(32),
            child: LinearProgressIndicator(
              value: (_counter / 10).clamp(0, 1),
              minHeight: 8,
            ),
          ),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton(
      key: const ValueKey('increment'),
      onPressed: () => setState(() => _counter++),
      tooltip: 'Increment',
      child: const Icon(Icons.add),
    ),
  );
}
