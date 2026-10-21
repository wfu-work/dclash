library;

import 'src/rust/frb_generated.dart';

export 'src/rust/api/hotkey.dart';
export 'src/rust/api/ipc.dart';
export 'src/rust/api/script.dart';
export 'src/rust/frb_generated.dart' show RustLib;

bool get isRustLibInitialized => RustLib.instance.initialized;

Future<void>? _initialization;

/// Shares native library initialization between profile evaluation and IPC.
Future<void> ensureRustLibInitialized() async {
  final inProgress = _initialization;
  if (inProgress != null) return inProgress;
  if (isRustLibInitialized) return;
  final initializing = RustLib.init();
  _initialization = initializing;
  try {
    await initializing;
  } finally {
    if (identical(_initialization, initializing)) _initialization = null;
  }
}
