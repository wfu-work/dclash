# Resource Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 dclash 中实现四类可复用资源库，并让 Profile Builder 能安全选择和应用这些资源。

**Architecture:** `ResourceItem` 负责不可变数据和序列化，`ResourceLibraryService` 负责校验、持久化、刷新和内容解析，`ResourceLibraryController/View` 负责工具页交互。资源数据以版本化 JSON 字符串存入 `SettingsService`，因此现有 `BackupService` 的 settings 快照会自动携带资源库；Profile Builder 通过明确的 draft 方法导入代理、provider、过滤器和图标，不直接修改持久化设置。

**Tech Stack:** Flutter 3.x, Dart 3.12, GetX 4.7, SharedPreferences, file_picker, yaml parser, existing `boundedHttp`, existing app widgets and localization.

**Spec:** `docs/superpowers/specs/2026-10-21-resource-library-design.md`

## Global Constraints

- 资源类型固定为 `proxy`、`ruleProvider`、`regexFilter`、`iconSet`。
- 资源来源固定为 `url`、`file`、`inline`；URL 仅允许 HTTP/HTTPS。
- 资源 JSON 版本为 1，保存前校验名称、来源、正则和 YAML。
- 下载失败、文件读取失败或恢复失败时保留上一份有效数据。
- 资源内容、URL 和订阅凭据不得写入日志或测试输出。
- 继续使用 Flutter + GetX、现有 AppCard/AppPage/AppEmpty/AppSettingsRow 组件和中英文翻译。
- 当前工作区没有 Git 仓库，不创建提交；每个任务仍必须完成对应的 focused test/checkpoint。

### Task 1: Resource domain model and validation

**Files:**
- Create: `lib/domains/resource_item.dart`
- Create: `test/resources/resource_item_test.dart`

**Interfaces:**
- Produces `enum ResourceKind { proxy, ruleProvider, regexFilter, iconSet }`.
- Produces `enum ResourceSourceType { url, file, inline }`.
- Produces immutable `ResourceItem` with `id`, `name`, `kind`, `sourceType`, `source`, `content`, `enabled`, `order`, `createdAt`, `updatedAt`, `extra`.
- Produces `ResourceItem.fromJson(Map<String,dynamic>)`, `toJson()`, `copyWith(...)`, `validate()`, and `ResourceEnvelope.decode/encode` preserving unknown item and envelope fields.

- [x] **Step 1: Write failing model tests**

```dart
test('round trips fields and preserves unknown fields', () {
  final item = ResourceItem.fromJson({
    'id': 'r1', 'name': 'Rules', 'kind': 'ruleProvider',
    'sourceType': 'inline', 'source': 'rules: []', 'enabled': true,
    'order': 2, 'createdAt': '2026-10-21T00:00:00Z',
    'updatedAt': '2026-10-21T00:00:00Z', 'future': {'x': 1},
  });
  expect(item.extra['future'], {'x': 1});
  expect(ResourceItem.fromJson(item.toJson()).id, 'r1');
});

test('rejects invalid URLs and regular expressions', () {
  final item = ResourceItem(
    id: 'bad-url',
    name: 'Bad URL',
    kind: ResourceKind.ruleProvider,
    sourceType: ResourceSourceType.url,
    source: 'ftp://example.invalid/rules.yaml',
    content: null,
    enabled: true,
    order: 0,
    createdAt: DateTime.utc(2026, 10, 21),
    updatedAt: DateTime.utc(2026, 10, 21),
  );
  expect(item.validate, throwsFormatException);
  expect(() => validateRegexContent('[', 'filter'), throwsFormatException);
});
```

- [x] **Step 2: Run model tests and verify they fail**

Run: `cd dclash-flutter && flutter test test/resources/resource_item_test.dart`
Expected: FAIL because the domain model and validators do not exist.

- [x] **Step 3: Implement the model**

Use string enum values in JSON, UTC ISO timestamps, non-negative order, deep-copied `extra` maps, and `ResourceEnvelope` with `version: 1`, `items`, and preserved unknown envelope keys. For inline resources use `source` as the content; URL/file resources may keep a validated cached `content`.

- [x] **Step 4: Run the focused tests**

Run: `cd dclash-flutter && flutter test test/resources/resource_item_test.dart`
Expected: PASS, including unknown-field round trip and all validation errors.

### Task 2: ResourceLibraryService persistence and refresh

**Files:**
- Modify: `lib/services/settings_service.dart`
- Create: `lib/services/resource_library_service.dart`
- Create: `test/resources/resource_library_service_test.dart`
- Modify: `lib/configs/app_initializer.dart`

**Interfaces:**
- `SettingsService.defaults` gains `resources: ''`; `_validated` accepts it as a string.
- `ResourceLibraryService(SettingsService settings)` exposes `RxList<ResourceItem> items`, `Future<void> initialize()`, `Future<ResourceItem> save(...)`, `Future<void> remove(String id)`, `Future<void> setEnabled(String id, bool enabled)`, `Future<void> reorder(String id, int order)`, `Future<ResourceItem> refresh(String id)`, `Future<String> resolveContent(ResourceItem item)`, and `List<ResourceItem> byKind(ResourceKind kind)`.
- `AppInitializer` registers and initializes the service before `BackupService`.

- [x] **Step 1: Add failing persistence and refresh tests**

Cover initialization from a versioned JSON string, CRUD with stable ids, same-kind duplicate names, enabled ordering, inline resolution, file resolution, successful URL refresh, and HTTP/file failure retaining old cached content. Use `SettingsService(memoryOnly: true)` and an injectable HTTP/file resolver so tests never access real subscriptions.

- [x] **Step 2: Run focused tests and verify failures**

Run: `cd dclash-flutter && flutter test test/resources/resource_library_service_test.dart`
Expected: FAIL because the service and `resources` setting are absent.

- [x] **Step 3: Implement service and validators**

Serialize through `SettingsService.set('resources', jsonEncode(...))` so writes are queued with other settings. Guard every mutation with validation and persist only after the full next envelope validates. Use `boundedHttp` with a bounded response for URL refresh; use `File.readAsString` for file resources; validate the fetched body before swapping it into the item. Keep the old item on every exception and expose a user-readable error through the thrown exception.

- [x] **Step 4: Register service in app initialization**

Create `final resources = ResourceLibraryService(settings); await resources.initialize(); Get.put(resources, permanent: true);` before constructing `BackupService`.

- [x] **Step 5: Run focused service tests**

Run: `cd dclash-flutter && flutter test test/resources/resource_library_service_test.dart`
Expected: PASS with no network or credential output.

### Task 3: Backup and restore coverage

**Files:**
- Modify: `lib/services/backup_service.dart` only if explicit resource envelope validation is needed.
- Modify: `test/profiles/backup_service_test.dart`

**Interfaces:**
- Existing `BackupService.exportArchive/importArchive` continues to carry the `resources` settings field.
- Add test fixtures that create resources through `ResourceLibraryService`, export, clear, import, and assert exact item restoration.

- [x] **Step 1: Add a failing resource round-trip test**

Assert inline content, enabled/order fields, and unknown item fields survive ZIP export/import; assert an invalid resource envelope rejects the whole restore and leaves existing settings unchanged.

- [x] **Step 2: Implement explicit validation hook if the test exposes a gap**

Validate `resources` with `ResourceEnvelope.decode` in the memory-only settings validator or in `BackupService` before applying settings. Do not apply settings or profiles until the complete payload validates.

- [x] **Step 3: Run backup tests**

Run: `cd dclash-flutter && flutter test test/profiles/backup_service_test.dart`
Expected: PASS, including rollback behavior.

### Task 4: Resource library controller and tools page

**Files:**
- Create: `lib/app/pages/tools/resource_library_controller.dart`
- Create: `lib/app/pages/tools/resource_library_view.dart`
- Modify: `lib/app/pages/tools/tools_view.dart`
- Modify: `lib/app/pages/workspace/workspace_binding.dart`
- Modify: `lib/configs/localization/feature_translations.dart`
- Create: `test/resources/resource_library_layout_test.dart`

**Interfaces:**
- `ResourceLibraryController(ResourceLibraryService service)` exposes `query`, `selectedKind`, `visibleItems`, `saveItem`, `removeItem`, `toggleItem`, `refreshItem`, and `pickFile`.
- `ResourceLibraryView` is a no-argument `const` page using `GetView<ResourceLibraryController>` and existing widgets.

- [x] **Step 1: Add layout tests**

Pump the view at a phone width and a desktop width, assert the resource title, kind filters, search field, empty state and add action render without overflow.

- [x] **Step 2: Implement controller and binding**

Register the controller in `WorkspaceBinding` with `Get.find<ResourceLibraryService>()`; keep all service mutations in controller methods and surface errors through the page.

- [x] **Step 3: Implement the view**

Add a tools row named “资源库 / Resource library”. Use four filter chips, `AppSearchField`, `AppEmpty`, compact resource cards, and an AlertDialog editor. The editor selects kind/source type, supports inline multiline text and URL/file paths, validates before save, and offers refresh/edit/enable/delete actions. Use line icons and current color scheme; never display full remote content in list rows.

- [x] **Step 4: Add translations and run layout tests**

Run: `cd dclash-flutter && flutter test test/resources/resource_library_layout_test.dart`
Expected: PASS at both widths with no overflow or untranslated resource labels.

### Task 5: Profile Builder resource selector and draft integration

**Files:**
- Create: `lib/app/pages/profiles/builder/resource_picker_dialog.dart`
- Modify: `lib/app/pages/profiles/builder/profile_builder_draft.dart`
- Modify: `lib/app/pages/profiles/profile_builder_view.dart`
- Modify: `lib/configs/localization/builder_translations.dart`
- Create: `test/profiles/resource_picker_test.dart`

**Interfaces:**
- `ProfileBuilderDraft.importProxyResource(String content)`, `addProviderResource(BuilderSection section, ResourceItem item)`, `applyRegexFilter(String content)`, and `applyIconSet(String content)` mutate only the draft document and preserve unrelated fields.
- `ResourcePickerDialog({required ResourceLibraryService service, required ResourceKind kind, required ValueChanged<ResourceItem> onSelected})` returns a selected enabled resource.

- [x] **Step 1: Add failing draft tests**

Test proxy YAML/list import, URL provider insertion with safe profile-relative path, regex filtering of proxy entries, icon-map application to proxy/group `icon` keys, duplicate-name handling, and preservation of unknown proxy fields.

- [x] **Step 2: Run focused tests and verify failures**

Run: `cd dclash-flutter && flutter test test/profiles/resource_picker_test.dart`
Expected: FAIL because draft resource methods and picker do not exist.

- [x] **Step 3: Implement draft methods**

Parse resource content using existing `parseConfig`, copy records before insertion, use `nextName`/provider validation, reject invalid or empty results, and apply edits through the existing draft config maps. For icon sets accept a mapping from proxy/group name to icon URL; for regex filters compile every pattern before applying the filter.

- [x] **Step 4: Add picker actions to Profile Builder**

Add a toolbar “Use resource” action whose kind follows the current section. Proxy/provider sections import records; a filter action filters the current proxy list; icon action sets icon fields. Mark the builder dirty only after a successful operation and show `showAppError` on invalid content. The picker shows only enabled resources and reports missing/deleted references without removing saved YAML.

- [x] **Step 5: Run focused builder tests**

Run: `cd dclash-flutter && flutter test test/profiles/resource_picker_test.dart`
Expected: PASS and all existing profile builder tests remain green.

### Task 6: Full verification and platform regression

**Files:**
- Modify: `docs/feature-parity.md` to mark resource-library coverage and remaining limitations.
- Modify: `README.md` only if the user-facing feature list needs the new resource library entry.

- [x] **Step 1: Run static analysis and all tests**

Run: `cd dclash-flutter && flutter analyze && flutter test && make check`
Expected: no analyzer errors; all required tests pass and optional platform tests are reported separately.

- [x] **Step 2: Build macOS and DMG**

Run: `cd dclash-flutter && make macos && make verify-macos && make dmg`
Expected: signed/checkable local app and a DMG under `build/releases/`.

- [x] **Step 3: Run Mumu Android smoke verification**

Use the existing Mumu emulator flow to install/launch the APK, open Tools → Resource library, create an inline rule resource, open Profile Builder, select it, save a profile, and reopen it. Do not include any subscription URL or secret in logs or output.

验证结果（2026-10-21）：使用 `emulator-5554`（Mumu，ARM64）安装并启动 `com.cloudrift.dclash`。在工具页资源库确认 `MumuRules3` 内联规则集已启用；在“配置 → 可视化编辑 → 使用资源 → 规则集”中选择该资源后，“规则提供器”由 `0` 变为 `1`。保存配置后退出编辑器并重新打开，仍显示“规则提供器 (1)”，确认资源引用已写入配置并可恢复。应用进程随后已停止；本次未启动真实代理核心、未申请 VPN 接管，也未输出订阅地址或凭据。

- [x] **Step 4: Record results**

Update `docs/feature-parity.md` with implemented surfaces and leave platform-dependent TUN/VPN limitations explicit. Link the generated DMG in the final response.
