import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleon/src/flutter/shared_load.dart';

void main() {
  test('every call shares one load until it finishes', () async {
    int loads = 0;
    final shared = SharedLoad(() async => loads += 1);

    await Future.wait([shared.load(), shared.load()]);
    await shared.load();
    shared.forgetUnfinished();
    await shared.load();
    expect(loads, 1, reason: 'a finished load is never forgotten');
  });

  test('a failed load is started again by the next call', () async {
    int loads = 0;
    final shared = SharedLoad(() async {
      loads += 1;
      if (loads == 1) throw StateError('no fonts');
    });

    await expectLater(shared.load(), throwsStateError);
    await shared.load();
    expect(loads, 2);
  });

  // A test that awaits the load under fake time ends before it does: its
  // teardown forgets the load, and the abandoned one, finishing or failing
  // later, never touches the load of the next test.
  test('a forgotten load leaves the next one alone', () async {
    final abandoned = Completer<void>();
    final next = Completer<void>();
    final pending = [abandoned, next];
    int loads = 0;
    final shared = SharedLoad(() {
      loads += 1;

      return pending.removeAt(0).future;
    });

    final first = shared.load();
    shared.forgetUnfinished();
    final second = shared.load();
    abandoned.completeError(StateError('abandoned'), .current);
    await expectLater(first, throwsStateError);
    expect(identical(shared.load(), second), isTrue, reason: 'still the load');
    next.complete();
    await second;
    shared.forgetUnfinished();
    await shared.load();
    expect(loads, 2);
  });
}
