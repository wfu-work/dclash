import 'dart:io';

Future<void> main(List<String> arguments) async {
  final repair = arguments.contains('--repair-ad-hoc-debug');
  final paths = arguments.where((value) => !value.startsWith('--')).toList();
  if (paths.length != 1) {
    stderr.writeln(
      'Usage: dart tool/verify_macos_bundle.dart <app> '
      '[--repair-ad-hoc-debug]',
    );
    exitCode = 64;
    return;
  }
  await verifyMacOSBundle(paths.single, repairAdHocDebug: repair);
}

/// Flutter can re-sign native asset frameworks after Xcode seals an incremental
/// bundle. Only an ad hoc Debug bundle with valid nested code can be resealed.
Future<void> verifyMacOSBundle(
  String path, {
  bool repairAdHocDebug = false,
}) async {
  final bundle = Directory(path).absolute;
  final verifyArguments = ['--verify', '--deep', '--strict', bundle.path];
  final verification = await Process.run('codesign', verifyArguments);
  if (verification.exitCode == 0) {
    stdout.writeln('Verified macOS bundle signature: ${bundle.path}');
    return;
  }
  final failure = '${verification.stdout}${verification.stderr}';
  final metadata = await _run('codesign', ['-dvvv', bundle.path]);
  final identity = _identity('${metadata.stdout}${metadata.stderr}');
  final isDebug =
      bundle.parent.path.split(Platform.pathSeparator).last == 'Debug';
  if (!repairAdHocDebug ||
      !isDebug ||
      identity['Signature'] != 'adhoc' ||
      !failure.contains('nested code is modified or invalid')) {
    throw ProcessException(
      'codesign',
      verifyArguments,
      failure,
      verification.exitCode,
    );
  }

  // Validate every nested framework and standalone Mach-O before touching the
  // outer seal. Do not use --deep when signing: no nested signatures are changed.
  final frameworks = Directory('${bundle.path}/Contents/Frameworks');
  if (await frameworks.exists()) {
    await for (final entity in frameworks.list(followLinks: false)) {
      if (entity is Directory && entity.path.endsWith('.framework')) {
        await _run('codesign', ['--verify', '--deep', '--strict', entity.path]);
      }
    }
  }
  final executable = await _run('plutil', [
    '-extract',
    'CFBundleExecutable',
    'raw',
    '${bundle.path}/Contents/Info.plist',
  ]);
  final executableName = (executable.stdout as String).trim();
  await for (final entity in Directory(
    '${bundle.path}/Contents/MacOS',
  ).list(followLinks: false)) {
    if (entity is! File ||
        entity.path.split(Platform.pathSeparator).last == executableName) {
      continue;
    }
    final file = await entity.open();
    final magic = await file.read(4);
    await file.close();
    final word = magic.fold<int>(0, (word, byte) => (word << 8) | byte);
    if (const {
      0xfeedface,
      0xfeedfacf,
      0xcefaedfe,
      0xcffaedfe,
      0xcafebabe,
      0xcafebabf,
      0xbebafeca,
      0xbfbafeca,
    }.contains(word)) {
      await _run('codesign', ['--verify', '--strict', entity.path]);
    }
  }
  final entitlements = await _run('codesign', [
    '-d',
    '--entitlements',
    ':-',
    bundle.path,
  ]);
  await _run('codesign', [
    '--force',
    '--sign',
    '-',
    '--preserve-metadata=identifier,entitlements,requirements,flags,runtime',
    bundle.path,
  ]);
  await _run('codesign', verifyArguments);
  final repairedMetadata = await _run('codesign', ['-dvvv', bundle.path]);
  final repairedIdentity = _identity(
    '${repairedMetadata.stdout}${repairedMetadata.stderr}',
  );
  final repairedEntitlements = await _run('codesign', [
    '-d',
    '--entitlements',
    ':-',
    bundle.path,
  ]);
  if (identity.entries.any(
        (entry) => repairedIdentity[entry.key] != entry.value,
      ) ||
      (entitlements.stdout as String).trim() !=
          (repairedEntitlements.stdout as String).trim()) {
    throw StateError(
      'macOS signature repair changed signing identity or entitlements.',
    );
  }
  stdout.writeln(
    'Resealed ad hoc Debug bundle; signing identity and entitlements preserved.',
  );
  stdout.writeln('Verified macOS bundle signature: ${bundle.path}');
}

Future<void> verifyBuiltMacOSBundle(List<String> arguments) async {
  if (arguments.contains('--config-only')) return;
  final configuration = arguments.contains('--debug')
      ? 'Debug'
      : arguments.contains('--profile')
      ? 'Profile'
      : 'Release';
  final configurationText = await File(
    'macos/Runner/Configs/AppInfo.xcconfig',
  ).readAsString();
  final name = RegExp(
    r'^\s*PRODUCT_NAME\s*=\s*(.+?)\s*$',
    multiLine: true,
  ).firstMatch(configurationText)?.group(1);
  if (name == null || name.contains('/') || name.contains(r'\')) {
    throw StateError('Could not resolve the macOS application name.');
  }
  await verifyMacOSBundle(
    'build/macos/Build/Products/$configuration/$name.app',
    repairAdHocDebug: configuration == 'Debug',
  );
}

Map<String, String?> _identity(String metadata) => {
  for (final field in [
    'Identifier',
    'Signature',
    'TeamIdentifier',
    'Runtime Version',
  ])
    field: RegExp(
      '^$field=(.*)\$',
      multiLine: true,
    ).firstMatch(metadata)?.group(1),
  'flags': RegExp(r' flags=([^\s]+)').firstMatch(metadata)?.group(1),
};

Future<ProcessResult> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}${result.stderr}',
      result.exitCode,
    );
  }
  return result;
}
