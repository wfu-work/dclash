import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    if (!input.config.buildCodeAssets) return;
    final staged = await _stageCrate(input, output);
    final originalDirectory = Directory.current;
    // Native hooks filter arbitrary environment variables, including
    // CARGO_HOME. Use explicit user-defines so the cache tracks this choice.
    final cargoHome = input.userDefines.path('cargo_home');
    if (cargoHome != null) {
      final config = File(
        p.join(Directory.fromUri(cargoHome).path, 'config.toml'),
      );
      if (await config.exists()) output.dependencies.add(config.uri);
    }
    final isolated = input.userDefines['cargo_isolated'] == true
        ? await Directory.systemTemp.createTemp('dclash-cargo-')
        : null;
    try {
      // Cargo also reads .cargo/config.toml in every ancestor of its cwd.
      // This opt-in allows a task-local CARGO_HOME to fully isolate registries.
      if (isolated != null) Directory.current = isolated;
      await FlutterRustBridgeNativeAssetsBuilder(
        cratePath: staged,
        extraCargoEnvironmentVariables: {
          ..._bindgenEnvironment(input),
          if (cargoHome != null)
            'CARGO_HOME': Directory.fromUri(cargoHome).path,
        },
      ).run(input: input, output: output);
    } finally {
      Directory.current = originalDirectory;
      if (isolated != null) await isolated.delete(recursive: true);
    }
  });
}

// rquickjs runs bindgen on Android, which must load the NDK's libclang; Linux
// NDKs before r26 keep it under lib64, later ones and every macOS NDK under lib.
Map<String, String> _bindgenEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets ||
      input.config.code.targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    return const {};
  }
  final llvmRoot = File.fromUri(compiler).parent.parent;
  for (final name in const ['lib', 'lib64']) {
    final directory = Directory(
      '${llvmRoot.path}${Platform.pathSeparator}$name',
    );
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return {'LIBCLANG_PATH': directory.path};
    }
  }
  throw StateError(
    'No libclang under ${llvmRoot.path} (lib or lib64); the NDK Flutter '
    'passed cannot run bindgen for rquickjs',
  );
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}

// A toolchain file listing every platform makes rustup download all cross
// compilers even for a host build. Stage the source with only this build target.
Future<String> _stageCrate(BuildInput input, BuildOutputBuilder output) async {
  final root = Directory.fromUri(input.packageRoot);
  final source = Directory(p.join(root.path, 'rust'));
  final staged = Directory.fromUri(
    input.outputDirectory.resolve('rust-source/'),
  );
  await staged.create(recursive: true);
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    if (p.split(relative).any((part) => part == 'target' || part == '.git')) {
      continue;
    }
    if (entity is! File) continue;
    output.dependencies.add(entity.uri);
    final target = File(p.join(staged.path, relative));
    await target.parent.create(recursive: true);
    final contents = await entity.readAsBytes();
    if (!await target.exists() ||
        !_sameBytes(contents, await target.readAsBytes())) {
      await target.writeAsBytes(contents);
    }
  }
  final architecture = input.config.code.targetArchitecture;
  final os = input.config.code.targetOS;
  final triple = switch ((os, architecture)) {
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc',
    (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc',
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    _ => throw UnsupportedError('DClash does not support $os $architecture'),
  };
  await File(p.join(staged.path, 'rust-toolchain.toml')).writeAsString(
    '[toolchain]\nchannel = "1.99.0"\nprofile = "minimal"\ntargets = ["$triple"]\n',
  );
  return p.relative(staged.path, from: root.path);
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
