import 'package:dclash_flutter/configs/theme/app_icon_paths.dart';
import 'package:dclash_flutter/configs/theme/app_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all bundled Lucide elements parse within their original viewport', () {
    for (final icon in AppIconPaths.icons) {
      final geometry = AppIconPaths.resolve(icon)!;
      final bounds = geometry.outline.getBounds();
      expect(bounds.isEmpty, false, reason: '$icon');
      expect(bounds.left, greaterThanOrEqualTo(-.5), reason: '$icon');
      expect(bounds.top, greaterThanOrEqualTo(-.5), reason: '$icon');
      expect(bounds.right, lessThanOrEqualTo(24.5), reason: '$icon');
      expect(bounds.bottom, lessThanOrEqualTo(24.5), reason: '$icon');
      expect(identical(AppIconPaths.resolve(icon), geometry), true);
    }
  });

  test('relative SVG elements keep an independent origin', () {
    final check = AppIconPaths.resolve(AppIcons.checkCircle)!.outline;
    expect(check.getBounds().bottom, closeTo(22, .01));
    final direct = AppIconPaths.resolve(AppIcons.navigation)!.outline;
    expect(direct.getBounds().top, 2);
    expect(direct.getBounds().right, 22);
  });
}
