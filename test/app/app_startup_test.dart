import 'package:dclash_flutter/configs/app_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connects on launch only when enabled with an active profile', () {
    expect(
      shouldConnectOnLaunch(
        preview: false,
        autoStart: true,
        hasActiveProfile: true,
      ),
      isTrue,
    );
    expect(
      shouldConnectOnLaunch(
        preview: false,
        autoStart: false,
        hasActiveProfile: true,
      ),
      isFalse,
    );
    expect(
      shouldConnectOnLaunch(
        preview: false,
        autoStart: true,
        hasActiveProfile: false,
      ),
      isFalse,
    );
    expect(
      shouldConnectOnLaunch(
        preview: true,
        autoStart: true,
        hasActiveProfile: true,
      ),
      isFalse,
    );
  });
}
