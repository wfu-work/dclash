# Per-profile standard extension

## Goal

补齐 Profile 的标准扩展模式：配置可以保存附加规则和 MATCH-TARGET，并在远程订阅刷新、核心启动、重载及有效配置预览时统一应用。

## Scope

- `ClashProfile` 保存 `standardRules` 与可选 `matchTarget`，旧索引缺省为空且兼容读取。
- `ConfigBuilder` 解析并前置配置级附加规则；`MATCH` 占位符使用配置的 MATCH-TARGET 替换。
- Profile 设置提供附加规则编辑、MATCH-TARGET 编辑和 LAN/本机直连等安全预设。
- ProfileService、核心启动/重载、有效配置预览、复制和备份恢复保留这些字段。
- 增加模型、规则构建、持久化和界面测试。

## Verification

- [x] 先运行新增 focused tests，确认按预期失败。
- [x] 完成后运行 focused tests、`flutter analyze`、`make check`。
- [x] 重新构建 macOS DMG；不启动真实 VPN。
