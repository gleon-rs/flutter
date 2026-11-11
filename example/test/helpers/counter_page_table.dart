import 'package:alchemist/alchemist.dart';
import 'package:gleon_example/counter_page.dart';
import 'package:material_ui/material_ui.dart';

/// The counter page as alchemist users lay out their goldens: a table of
/// scenarios, here at the default text size and enlarged. Shared by the
/// golden test and the benchmark, so both render the same image.
///
/// alchemist (0.14.1) provides only the localizations of the SDK's deprecated
/// Material library, which `material_ui` widgets do not read: the table adds
/// those of `material_ui`. Without a theme above it, the page takes the
/// fallback theme, as under alchemist's own.
class CounterPageTable extends StatelessWidget {
  /// Creates the table.
  const new({super.key});

  @override
  Widget build(BuildContext context) => Localizations.override(
    context: context,
    delegates: const [DefaultMaterialLocalizations.delegate],
    child: GoldenTestGroup(
      children: [
        GoldenTestScenario(name: 'default', child: _phone),
        GoldenTestScenario.withTextScaleFactor(
          name: 'large text',
          textScaler: const .linear(1.5),
          child: _phone,
        ),
      ],
    ),
  );
}

/// The page at a small phone's size (a `Scaffold` needs bounds).
const _phone = SizedBox(width: 240, height: 320, child: CounterPage());
