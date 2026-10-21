# Per-profile shared script selection

## Goal

让共享脚本库继续支持全局启用，同时允许单个配置选择参与构建的脚本；旧配置在没有选择记录时保持“使用全部已启用脚本”的行为。

## Scope

- `ClashProfile` 持久化可选的共享脚本 ID 列表，保留旧索引兼容性。
- `ConfigBuilder` 按配置选择过滤共享脚本，保持脚本库原有顺序并保留缺失 ID。
- 配置设置对话框提供“跟随脚本库”与脚本勾选器，未启用脚本不可被选中执行。
- 核心启动、重载、有效配置预览、复制和备份恢复都携带选择状态。
- 增加模型、构建、ProfileService 持久化与界面回归测试。

## Verification

- [x] 先运行新增 focused tests，确认在实现前按预期失败。
- [x] 完成实现后运行 focused tests、`flutter analyze`、`make check`。
- [x] 在 macOS 本机启动调试应用，确认新增配置设置代码可正常编译和启动；选择器交互由 focused widget test 覆盖。
