import 'package:dclash_flutter/domains/script_library.dart';
import 'package:dclash_flutter/services/config_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_api/rust_api.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'cold shared-script preview initializes QuickJS without a core session',
    () async {
      expect(isRustLibInitialized, false);
      try {
        final content = await ConfigBuilder.build('proxies: []', {
          'scripts': ScriptLibrary(
            scripts: [
              LibraryScript(
                id: 'native-smoke',
                name: 'Native smoke',
                enabled: true,
                content:
                    'function main(config) { config.nativeSmoke = "passed"; return config; }',
              ),
            ],
          ).encode(),
        });
        expect(isRustLibInitialized, true);
        expect(loadYaml(content)['nativeSmoke'], 'passed');
      } finally {
        if (isRustLibInitialized) RustLib.dispose();
      }
    },
    skip: !const bool.fromEnvironment('DC_NATIVE_SCRIPT_SMOKE'),
  );
}
