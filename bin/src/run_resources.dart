/// What a run of `bin/consumer_check.dart` leaves behind until it is cleaned
/// up. Only `dart:*` and `src/` may be imported here.
library;

import 'dart:async';
import 'dart:io';

import 'release_server.dart';
import 'stray_home_config.dart';

/// The release server, a stray home config and the work directory (unless
/// kept) of one run.
final class RunResources {
  /// The resources of a run in [work].
  RunResources(this.work, {required this.isKept});

  /// The directory of the run.
  final Directory work;

  /// Whether [work] stays for a look after the run.
  final bool isKept;

  /// The local release, once started.
  ReleaseServer? server;

  /// The stray `~/.gleon/gleon.yaml`, once written.
  StrayHomeConfig? stray;

  bool _isCleaned = false;

  /// Cleans up once, whoever asks first (the end of the run, an interrupt).
  Future<void> cleanUp() async {
    if (_isCleaned) return;
    _isCleaned = true;
    stray?.remove();
    await server?.close();
    if (isKept) {
      stdout.writeln('consumer_check: kept ${work.path}');
    } else if (work.existsSync()) {
      work.deleteSync(recursive: true);
    }
  }

  /// Cleans up after [signal] (Ctrl+C, a cancelled CI job: both skip
  /// `finally`) and exits as an interrupted process does.
  void interrupt(ProcessSignal signal) {
    stderr.writeln('consumer_check: $signal, cleaning up.');
    unawaited(_exitClean());
  }

  Future<void> _exitClean() async {
    await cleanUp();
    exit(130);
  }
}
