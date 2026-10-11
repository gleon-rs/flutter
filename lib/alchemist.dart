/// Puts gleon behind alchemist's golden tests without depending on
/// alchemist: assign `gleonAlchemistExpectation()` to alchemist's
/// `goldenFileExpectationFn` in `test/flutter_test_config.dart` (see the
/// README's "Golden harnesses").
library;

export 'src/flutter/alchemist_expectation.dart'
    show AlchemistGoldenExpectation, gleonAlchemistExpectation;
