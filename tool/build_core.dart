import 'dart:io';

Future<void> main(List<String> args) async {
  final result = await Process.start(Platform.resolvedExecutable, [
    '--packages=.dart_tool/package_config.json',
    'plugins/setup/setup_hooks/bin/build.dart',
    ...args,
  ], mode: ProcessStartMode.inheritStdio);
  exitCode = await result.exitCode;
}
