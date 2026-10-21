import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

String randomIdentifier() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// A same-directory rename commits complete, flushed data in one filesystem step.
Future<void> writePrivateAtomic(File target, List<int> bytes) async {
  await target.parent.create(recursive: true);
  final temporary = File(
    p.join(
      target.parent.path,
      '.${p.basename(target.path)}.${randomIdentifier()}.tmp',
    ),
  );
  try {
    final handle = await temporary.open(mode: FileMode.writeOnly);
    try {
      restrictFilePermissions(temporary.path);
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temporary.rename(target.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<void> writePrivateText(File target, String text) =>
    writePrivateAtomic(target, utf8.encode(text));

void restrictFilePermissions(String path) {
  if (Platform.isWindows) return;
  final nativePath = path.toNativeUtf8();
  try {
    final chmod = DynamicLibrary.process()
        .lookupFunction<
          Int32 Function(Pointer<Utf8>, Uint32),
          int Function(Pointer<Utf8>, int)
        >('chmod');
    if (chmod(nativePath, 0x180) != 0) {
      throw FileSystemException(
        'Unable to protect private configuration permissions',
        path,
      );
    }
  } finally {
    malloc.free(nativePath);
  }
}
