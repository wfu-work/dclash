import 'dart:io';

Future<void> main(List<String> arguments) async {
  final file = File('pubspec.yaml');
  final original = await file.readAsString();
  try {
    await file.writeAsString(
      original.replaceAll('build_assets: true', 'build_assets: false'),
    );
    final process = await Process.start('flutter', [
      'test',
      ...arguments,
    ], mode: ProcessStartMode.inheritStdio);
    exitCode = await process.exitCode;
  } finally {
    await file.writeAsString(original);
  }
}
