import 'package:flutter/material.dart';

import 'counter_page.dart';

void main() => runApp(const Main());

class Main extends StatelessWidget {
  /// Creates the app.
  const Main({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: const CounterPage(),
    title: 'gleon counter',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    debugShowCheckedModeBanner: false,
  );
}
