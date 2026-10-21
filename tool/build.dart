import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'verify_macos_bundle.dart';

/// Builds a Flutter target with optional explicit native-hook configuration.
/// Run serially with other Flutter commands, including tool/test.dart.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first.startsWith('-')) {
    stderr.writeln(
      'Usage: dart tool/build.dart <target> '
      '[--isolated-cargo-home=<path>] [flutter build options]',
    );
    exitCode = 64;
    return;
  }
  await buildFlutter(arguments.first, arguments.skip(1).toList());
}

/// Passes an optional isolated Cargo home through the native hook's explicit
/// configuration. Native hook processes strip arbitrary environment variables.
Future<void> buildFlutter(String target, List<String> arguments) async {
  const option = '--isolated-cargo-home=';
  final cargoOptions = arguments.where((value) => value.startsWith(option));
  if (cargoOptions.length > 1) {
    throw ArgumentError('Only one isolated Cargo home can be provided.');
  }
  final cargoOption = cargoOptions.firstOrNull;
  final flutterArguments = arguments
      .where((value) => !value.startsWith(option))
      .toList();
  final pubspec = File('pubspec.yaml');
  final original = await pubspec.readAsString();
  var configured = original;
  if (cargoOption != null) {
    final path = cargoOption.substring(option.length);
    if (path.isEmpty) {
      throw ArgumentError('An isolated Cargo home is required.');
    }
    final cargoHome = Directory(path).absolute;
    await cargoHome.create(recursive: true);
    final section = RegExp(r'^    rust_api:\r?$', multiLine: true);
    if (section.allMatches(original).length != 1 ||
        RegExp(
          r'^      cargo_(home|isolated):',
          multiLine: true,
        ).hasMatch(original)) {
      throw StateError('Expected one unconfigured rust_api hook section.');
    }
    configured = original.replaceFirst(
      section,
      '    rust_api:\n'
      '      cargo_home: ${jsonEncode('${cargoHome.path}${Platform.pathSeparator}')}\n'
      '      cargo_isolated: true',
    );
  }
  final signals = <StreamSubscription<ProcessSignal>>[];
  try {
    if (configured != original) await pubspec.writeAsString(configured);
    final process = await Process.start('flutter', [
      'build',
      target,
      ...flutterArguments,
    ], mode: ProcessStartMode.inheritStdio);
    for (final signal in [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ]) {
      signals.add(signal.watch().listen((_) => process.kill(signal)));
    }
    exitCode = await process.exitCode;
    if (exitCode == 0 && target == 'macos') {
      await verifyBuiltMacOSBundle(flutterArguments);
    }
  } finally {
    for (final signal in signals) {
      await signal.cancel();
    }
    if (configured != original) await pubspec.writeAsString(original);
  }
}
