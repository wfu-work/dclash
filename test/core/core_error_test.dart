import 'package:dclash_flutter/platform/core_error.dart';
import 'package:dclash_flutter/platform/core_rpc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies core failures for user-facing status labels', () {
    expect(
      classifyCoreError(const CoreException('system_proxy', 'proxy failed')),
      CoreErrorCategory.systemProxy,
    );
    expect(
      classifyCoreError(
        const CoreException('helper_missing', 'install helper'),
      ),
      CoreErrorCategory.tun,
    );
    expect(
      classifyCoreError(
        const CoreException('android_init', 'VPN service unavailable'),
      ),
      CoreErrorCategory.tun,
    );
    expect(
      classifyCoreError(
        const CoreException('android_start', 'VPN permission was denied'),
      ),
      CoreErrorCategory.permission,
    );
    expect(
      classifyCoreError(const CoreException('timeout', 'request timed out')),
      CoreErrorCategory.timeout,
    );
    expect(
      classifyCoreError(const CoreException('process_exit', 'core exited')),
      CoreErrorCategory.process,
    );
    expect(
      classifyCoreError(const FormatException('invalid yaml config')),
      CoreErrorCategory.configuration,
    );
  });
}
