import 'dart:io';

import 'flutter_command.dart' as flutter_command;

Future<void> main(List<String> arguments) async {
  final file = File('pubspec.yaml');
  final original = await file.readAsString();
  try {
    await file.writeAsString(
      original.replaceAll('build_assets: true', 'build_assets: false'),
    );
    exitCode = await flutter_command.runFlutter(['test', ...arguments]);
  } finally {
    await file.writeAsString(original);
  }
}
