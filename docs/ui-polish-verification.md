# Codexc 风格界面验证

日期：2026-10-20。范围为本轮图标、排版、公共组件、响应式布局与 Android 沉浸式系统栏。视觉规范见 [UI_STYLE_GUIDE.md](UI_STYLE_GUIDE.md)；功能完成情况仍以 [功能对照](feature-parity.md) 为准。

## 自动化检查

| 检查 | 结果 | 日志 |
| --- | --- | --- |
| Dart 格式化 | 本轮修改的 `lib` 与 `test/app` 文件已格式化 | — |
| `flutter analyze --no-pub` | 通过，No issues found | `build/verification/ui-polish-analyze.log` |
| 完整应用测试 | **102 项通过，1 项可选原生脚本检查跳过** | `build/verification/ui-polish-tests.log` |
| 最后补充的配置卡片布局检查 | 通过 | `build/verification/ui-polish-populated.log` |
| macOS Debug 预览构建 | 通过，deep / strict bundle 签名检查通过 | `build/verification/ui-polish-macos-build.log` |
| Android ARM64 Debug 预览构建 | 通过 | `build/verification/ui-polish-android-preview-build.log` |
| Android ARM64 普通 Debug 构建 | 通过，APK v2 签名验证通过 | `build/verification/ui-polish-android-build.log`、`ui-polish-android-signature.log` |

新增检查覆盖 85 个 Lucide 图标的原始坐标边界、独立 SVG 元素的相对坐标、几何缓存，以及系统栏主题与导航安全区。布局检查覆盖 320dp 宽度、1.5 倍文字、长配置名与节点名，以及 1240dp 桌面宽度和 1.2 倍文字。

macOS 构建仍会报告本机 CoreSimulator 与 Xcode 版本不匹配，但 macOS 产物构建和签名检查成功。Android 构建提示 `file_picker` / `package_info_plus` 后续需适配 Built-in Kotlin；本次 Gradle 构建成功。

## 原生界面检查

只运行带 `DC_PREVIEW=true` 的预览实例，使用内存设置和临时配置。没有启动 VPN、TUN、系统代理或特权辅助程序。

macOS 检查了浅色仪表盘、代理页、设置与外观页，以及深色仪表盘和代理页。导航、搜索、卡片、返回 / 关闭及主题控件均呈现统一的细线图标；标题、正文、辅助信息与边框层级清楚，没有观察到文字溢出或图标裁切。预览通过原生关闭按钮退出，并确认记录的 PID 已结束。

Android 使用本次启动的只读 Pixel 6 模拟器（API 36、ARM64、1080×2400、420dpi），安装预览 APK，检查仪表盘 → 工具 → 外观 → 深色 → 仪表盘。点击坐标从 UI 自动化树的控件边界计算。浅色系统栏显示深色图标；深色系统栏显示浅色图标。状态栏和手势导航背景与页面衔接，系统时间、电量和导航仍可见，底部导航避让手势区。应用进程日志未发现 Flutter 异常、RenderFlex 溢出或致命崩溃。

截图中的“界面预览”提示属于预览模式；Android 右侧悬浮图标属于模拟器已有的工具覆盖层。

| 截图 | 文件 |
| --- | --- |
| 桌面浅色仪表盘 | [查看](screenshots/ui-desktop-dashboard-light.png) |
| 桌面深色仪表盘 | [查看](screenshots/ui-desktop-dashboard-dark.png) |
| 桌面深色外观 | [查看](screenshots/ui-desktop-appearance-dark.png) |
| 桌面深色代理 | [查看](screenshots/ui-desktop-proxies-dark.png) |
| Android 浅色仪表盘 | [查看](screenshots/ui-android-dashboard-light.png) |
| Android 深色仪表盘 | [查看](screenshots/ui-android-dashboard-dark.png) |
| Android 深色外观 | [查看](screenshots/ui-android-appearance-dark.png) |

## 产物与复现

所有 Flutter 测试和构建串行执行，构建包装脚本已恢复 `pubspec.yaml`。Cargo 继续使用工作区内的 `.dart_tool/cargo-home`。

```sh
dart tool/test.dart --no-pub --concurrency=2 --reporter=expanded
flutter analyze --no-pub
dart tool/build_macos.dart --isolated-cargo-home=.dart_tool/cargo-home --debug --no-pub --dart-define=DC_PREVIEW=true
dart tool/build.dart apk --isolated-cargo-home=.dart_tool/cargo-home --debug --no-pub --target-platform=android-arm64 --split-per-abi --dart-define=DC_PREVIEW=true
# 先复制预览 APK，再生成普通 APK，避免混淆最终产物。
dart tool/build.dart apk --isolated-cargo-home=.dart_tool/cargo-home --debug --no-pub --target-platform=android-arm64 --split-per-abi
```

- 普通 Android APK：`build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`，包名 `com.cloudrift.dclash`。
- 普通 APK SHA-256：`2ac0df10b6184f59b43c3c2958de24584bccc78a4e08b7f60e989243379c91a9`。
- Android 预览 APK：`build/verification/cloudrift-ui-preview-arm64.apk`。
- macOS 预览：`build/macos/Build/Products/Debug/Cloudrift.app`。

本轮验收覆盖界面与构建；真实 VPN 流量、授权流程及其他平台验收沿用 [既有验证记录](verification.md) 中的待办，不作为本轮通过项。
