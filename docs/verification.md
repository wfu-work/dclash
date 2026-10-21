# 验证记录

本页保留上一轮功能迁移的验证结果。最新界面检查、Android 模拟器预览、构建日志与 APK 校验值见 [Codexc 风格界面验证](ui-polish-verification.md)。

本记录区分源码实现、自动化检查和真实设备验收。参考版本为 FlClash v0.9.1；尚未完成全部功能与界面的逐项对应，具体差异见 [功能对照](feature-parity.md)。

## 环境与检查结果

本机使用 Flutter 3.44.5、Dart 3.12.2、Go 1.27、Rust 1.99.0；macOS 最低部署版本为 12。

| 检查 | 结果 |
| --- | --- |
| `dart format lib test tool` | 已执行；最后修改的 Dart 文件均再次格式化。 |
| `flutter analyze --no-pub` | 通过，No issues found。日志：`build/verification/flutter-analyze-final.log`。 |
| `dart tool/test.dart --no-pub --concurrency=2` | **98 项通过**。日志：`build/verification/flutter-tests-final.log`。 |
| `dart tool/test.dart --no-pub plugins/proxy/test` | **26 项通过**，通过注入进程执行器验证，没有修改主机代理。 |
| Go IPC / 配置测试子集，`CGO_ENABLED=0` | 通过：帧读写、参数校验、默认值、无效配置保留原有状态。 |
| 临时目录中的真实 Go sidecar RPC 检查 | 通过：版本、初始化、配置、流量、拒绝无效配置、关闭和所属进程退出；未启动监听或建立 Internet socket。 |
| 真实 Rust / QuickJS 冷启动检查 | **1 项通过**：只启用共享脚本、没有配置专属脚本时，默认 `ConfigBuilder` 能加载实际构建的 Rust framework 并得到脚本修改后的配置。日志：`build/verification/native-script-smoke.log`。 |
| macOS debug，`DC_PREVIEW=true` | 最终构建通过，Go sidecar / Rust framework 已嵌入；bundle 的 deep / strict 签名检查通过。 |
| Android ARM64 完整 debug APK | 最终构建通过，包内仅 `arm64-v8a`，包含 Flutter、Go 和 Rust，v2 签名检查通过；未安装或运行。 |

98 项应用测试覆盖配置与设置的持久化失败、备份校验及回滚、生命周期和 RPC、启动过程中的模式变更、代理恢复重试、脚本顺序与错误、恢复设置期间远程脚本刷新的写入竞争、Android 应用列表选择、配置构建器与规则引用，以及 390×844 / 1240×850 界面与深浅主题。

配置构建器回归包括 `sub-rules`、嵌套逻辑 `RULE-SET`、`src` / `no-resolve` 参数、子规则与代理的独立命名空间、未知字段保留、组环检测和原有自定义 `GLOBAL` 组编辑。

## 界面预览

仅启动编译时显式设置 `DC_PREVIEW=true` 的 macOS 应用。设置保存在内存，配置保存在本次预览的临时目录；界面显示预览标记，核心和网络接管操作被拒绝。

已检查桌面仪表盘、代理页和约 402 逻辑像素宽度的移动布局，确认侧栏切换为底部导航。之后检查了自定义配置创建与保存、配置操作菜单、五部分可视化构建器、节点表单 / 高级 YAML 入口、设置和共享脚本编辑器。最终签名后的新实例还验证了新建 / 启用本地共享脚本、创建配置，以及在从未连接核心时打开有效配置预览。预览应用通过原生关闭按钮退出，并确认任务记录的 PID 已结束。

这些检查没有启动 VPN、TUN 或系统代理，没有安装特权辅助程序，也没有改变开机启动设置。

## 产物与复现

所有 Flutter 测试和构建在同一个目录内串行运行；包装脚本会临时修改原生 hook 配置，并在结束时恢复 `pubspec.yaml`。请直接执行 `dart tool/test.dart`，不要使用 `dart run`。

```sh
dart tool/test.dart --no-pub --concurrency=2
flutter analyze --no-pub
dart tool/build_macos.dart --isolated-cargo-home=.dart_tool/cargo-home --debug --no-pub --dart-define=DC_PREVIEW=true
dart tool/build.dart apk --isolated-cargo-home=.dart_tool/cargo-home --debug --no-pub --target-platform=android-arm64 --split-per-abi
```

- macOS 产物：`build/macos/Build/Products/Debug/Cloudrift.app`；构建日志：`build/verification/macos-preview-final.log`。
- Android 最终分包：`build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`；最终日志：`build/verification/android-arm64-debug-apk-final.log`。
- Android SHA-256：`065313846a2e06b316909d2945138a3f8d1b51d8240fc5a63a517bc6cc45cca9`；包名 `com.cloudrift.dclash`，名称 `云渡 Cloudrift`。

macOS 增量构建中，Flutter 更新并重新签名了内嵌框架，而 Xcode 没有更新应用外层签名。构建包装脚本已增加收尾校验：只对所有内嵌代码各自校验通过的 ad hoc Debug 应用重封外层签名，并确认标识、entitlements 和签名元数据保持一致。其他配置或签名错误会直接使构建失败。

构建使用工作区内 `.dart_tool/cargo-home`，未修改用户全局 Cargo registry 配置。macOS 构建期间 Xcode 报告本机 CoreSimulator 版本不匹配警告；此前 macOS 构建仍成功，未更改系统 Xcode 或模拟器安装。

原生脚本检查使用可选的 `test/native/script_runtime_test.dart`，普通测试运行会跳过此项。要运行它，先将本机构建的 Rust 动态库放在任务目录下可定位的位置，再以 `FRB_DART_LOAD_EXTERNAL_LIBRARY_NATIVE_LIB_DIR` 指定该目录，并执行：

```sh
dart tool/test.dart --no-pub --dart-define=DC_NATIVE_SCRIPT_SMOKE=true test/native/script_runtime_test.dart
```

本次使用 `build/verification/native-script-sandbox/librust_api.dylib` 指向当前应用中构建的 Rust framework；整个检查只执行配置脚本，没有创建核心会话。

## 尚未验收

Android APK 未安装或运行，应用枚举权限、VPN 授权及真实流量需在目标设备验证。Windows / Linux 尚未在对应宿主构建或运行；iOS 未实现。系统代理恢复、TUN 路由、管理员授权、辅助服务安装、开机启动和原生文件选择器仍需平台验收。

Linux / Windows 的当前系统代理清理会关闭本应用设置的代理，尚不具备 macOS 已实现的完整旧设置快照与恢复。FlClash 备份格式的直接互通未验证；当前备份采用 Cloudrift 自身格式。完整功能差异和后续补齐项以 [功能对照](feature-parity.md) 为准。
