// Console markers read better as symbols than as ASCII.
// ignore_for_file: avoid-non-ascii-symbols

/// Result of one golden comparison, as recorded in its case report.
enum CaseOutcome {
  /// Different image sizes.
  dimensionMismatch('dimension_mismatch', '≠'),

  /// The engine could not compare (e.g. a corrupt PNG).
  error('error', '!'),

  /// Byte-identical PNGs, decided without the native engine.
  identical('identical', '='),

  /// Within the tolerance.
  match('match', '✓'),

  /// Beyond the tolerance.
  mismatch('mismatch', '✗'),

  /// The golden was rewritten (`--update-goldens`); nothing was compared.
  updated('updated', '↻');

  CaseOutcome(this.json, this.symbol);

  /// The `outcome` value in the case report.
  final String json;

  /// One-character marker for console lines.
  final String symbol;
}
