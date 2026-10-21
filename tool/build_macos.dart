import 'build.dart' as native_build;

/// Compatibility entry point for the original macOS build command.
Future<void> main(List<String> arguments) =>
    native_build.buildFlutter('macos', arguments);
