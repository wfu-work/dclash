import 'package:dclash_flutter/services/desktop_integration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tray labels are Chinese and do not depend on the app locale', () {
    expect(DesktopTrayText.label('hideWindow'), '隐藏窗口');
    expect(DesktopTrayText.label('status'), '运行状态');
    expect(DesktopTrayText.label('stopped'), '未连接');
    expect(DesktopTrayText.label('running'), '运行中');
    expect(DesktopTrayText.label('outboundMode'), '出站模式');
    expect(DesktopTrayText.label('rule'), '规则');
    expect(DesktopTrayText.label('global'), '全局');
    expect(DesktopTrayText.label('direct'), '直连');
    expect(DesktopTrayText.label('systemProxy'), '系统代理');
    expect(DesktopTrayText.label('quit'), '退出 dclash');
  });

  test('unknown tray labels remain identifiable for future additions', () {
    expect(DesktopTrayText.label('newTrayAction'), 'newTrayAction');
  });
}
