import 'dart:async';
import 'dart:io';

/// Runs one Flutter command while holding a repository-wide process lock.
///
/// Flutter itself has an SDK startup lock, but concurrent commands otherwise
/// race while rewriting pubspec/build metadata.  The OS file lock is released
/// automatically when this process exits, including after a forced stop.
Future<int> runFlutter(List<String> arguments) async {
  final lockDirectory = Directory('.dart_tool');
  await lockDirectory.create(recursive: true);
  final lockFile = File(
    '${lockDirectory.path}${Platform.pathSeparator}flutter-command.lock',
  );
  final lock = await lockFile.open(mode: FileMode.writeOnlyAppend);
  try {
    await lock.lock(FileLock.blockingExclusive);
    final executable = Platform.environment['DCLASH_FLUTTER']?.trim();
    final flutter = executable == null || executable.isEmpty
        ? (Platform.isWindows ? 'flutter.bat' : 'flutter')
        : executable;
    final process = await Process.start(
      flutter,
      arguments,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    final signals = <StreamSubscription<ProcessSignal>>[];
    try {
      for (final signal in [
        ProcessSignal.sigint,
        if (!Platform.isWindows) ProcessSignal.sigterm,
      ]) {
        signals.add(signal.watch().listen((_) => process.kill(signal)));
      }
      return await process.exitCode;
    } finally {
      for (final signal in signals) {
        await signal.cancel();
      }
    }
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

Future<void> main(List<String> arguments) async {
  exitCode = await runFlutter(arguments);
}
