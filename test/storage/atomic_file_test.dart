import 'dart:io';

import 'package:dclash_flutter/storage/atomic_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overwrites an existing file on repeated atomic writes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dclash_atomic_file_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final target = File(
      '${directory.path}${Platform.pathSeparator}config.json',
    );
    await writePrivateText(target, 'first');
    await writePrivateText(target, 'second');

    expect(await target.readAsString(), 'second');
    expect(
      directory.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.tmp'),
      ),
      isEmpty,
    );
  });
}
