import 'dart:async';

import 'package:flutter/foundation.dart';

/// One load every caller shares until it finishes (the fonts of
/// `loadAppFonts`). A load that fails, or that is forgotten unfinished
/// ([forgetUnfinished]: a test that awaited it under fake time ended), is
/// started again by the next call; a forgotten load that finishes or fails
/// later never touches the next one.
final class SharedLoad {
  /// Shares the loads of [_onLoad].
  SharedLoad(this._onLoad);

  final AsyncCallback _onLoad;

  /// The current load: its completion, which also tells it apart from the
  /// loads it replaced.
  Completer<void>? _current;

  /// The shared load, started when none is running or done.
  Future<void> load() {
    if (_current case final current?) return current.future;
    final load = Completer<void>();
    _current = load;
    unawaited(_run(load));

    return load.future;
  }

  /// Forgets the current load unless it finished.
  void forgetUnfinished() {
    if (_current case final current? when !current.isCompleted) {
      _current = null;
    }
  }

  Future<void> _run(Completer<void> load) async {
    try {
      await _onLoad();
      load.complete();
    } on Object catch (error, stackTrace) {
      if (identical(_current, load)) _current = null;
      load.completeError(error, stackTrace);
    }
  }
}
