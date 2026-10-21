import 'dart:io';
import 'package:setup_hooks/src/build.dart';
import 'package:setup_hooks/src/target.dart';

Future<void> main(List<String> args) async {
  final platform = Platform.isMacOS ? 'macos' : Platform.operatingSystem;
  final arch = args.isEmpty
      ? (Platform.version.contains('arm64') ? 'arm64' : 'amd64')
      : args.first;
  final report = await buildPlatform(
    BuildRequest(
      rootDir: Directory.current.path,
      target: Target.resolve(platform: platform, goarch: arch),
    ),
  );
  for (final output in report.outputs) {
    stdout.writeln(output);
  }
}
