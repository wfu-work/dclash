# FlClash feature parity inventory

This inventory compares the checked-in FlClash reference (`../FlClash`, version `0.9.1+2026101702`) with the current Cloudrift implementation. It records source coverage, not a claim that every native operation has been exercised. Real VPN starts and host networking changes are excluded from development verification. Full feature and interface parity has **not** been reached.

“Implemented” means a reachable UI calls the corresponding service or changes the actual stored configuration. “Partial” means the main flow exists with missing controls or reduced behavior. “Missing” means no equivalent user-facing surface exists. The retained Go core can support capabilities that the Flutter application does not yet expose.

## Application and dashboard

| FlClash surface | Cloudrift source | Status and remaining work |
| --- | --- | --- |
| Desktop sidebar/mobile navigation (`views/navigation.dart`) | `app/pages/workspace` | Implemented: adaptive navigation, retained visited pages, keyboard page shortcuts. Navigation item customization is missing. |
| Core start/stop/status (`dashboard/widgets/core_status_button.dart`) | `dashboard/widgets/status_card.dart`, `services/core_service.dart` | Implemented in source with explicit start, lifecycle state and errors. Real VPN/device acceptance remains unverified. |
| Traffic chart, totals, uptime | `dashboard/widgets/traffic_card.dart`, `dashboard_controller.dart` | Implemented: bounded histories and live service metrics. Upstream traffic-statistics preferences are missing. |
| Rule/global/direct and network takeover | `dashboard_view.dart`, settings network section | Implemented in source: persisted mode/system proxy/TUN controls. Native permissions and host effects need platform validation. |
| Current profile, proxy groups, recent connections, memory | `dashboard_view.dart` | Implemented overview cards. Dedicated connection statistics and intranet IP cards are missing. |
| Current outbound IP | `DashboardController.detectIp` | Partial: a single IP source is exposed, invalid responses are rejected, and route changes clear results and discard late replies. Upstream source selection and region details remain missing. |
| Service unlock/status checks | `DashboardController.checkServices` | Partial: four services are presented; upstream includes thirteen services and richer region/status treatment. |
| Dashboard edit/style/widget registry (`dashboard/edit.dart`, `style.dart`, `widget_registry.dart`) | `DashboardLayoutView`, persistent `dashboardCards` | Partial: card visibility and drag ordering are implemented, with adaptive pairing. Free resize, widget registry and visual-style preferences remain missing. |

## Proxies and profiles

| FlClash surface | Cloudrift source | Status and remaining work |
| --- | --- | --- |
| Proxy groups, selection, search | `app/pages/proxies` | Implemented: selector groups call `selectProxy`; non-selector groups remain read-only. |
| List/card style, sort, hide timeout nodes | `ProxiesController`, `ProxyNodeTile` | Implemented: persisted list/grid, original/name/delay order, hide unavailable, individual/all latency tests. Upstream density/card size/icon styles and extra group navigation layouts remain missing. |
| Proxy providers | `settings/providers_view.dart` | Partial: provider count/type and refresh are exposed. Provider inspection, health-check and richer provider node UI need parity work. |
| URL/file/custom import | `app/pages/profiles`, `ProfileService` | Implemented: subscription/file import and new YAML configuration. QR scanning/import is missing. Native file flows need platform verification. |
| Activate/refresh/duplicate/export/remove | `ProfilesController`, `ProfilesView` | Implemented with async errors and active-profile handling. Bulk actions, manual ordering/sort and upstream context-menu interactions remain missing. |
| Subscription usage/expiry | `profiles/widgets/profile_card.dart` | Implemented when subscription response headers supply statistics. |
| Profile name/URL/update interval | `profile_settings_dialog.dart`, `ProfileService` | Implemented with persisted auto-update interval. Upstream uses finer interval controls; AGE secret/decryption support is missing. |
| Raw/effective profile preview (`profiles/preview.dart`, `pages/editor.dart`) | `ProfileEditor`, `EffectiveConfigView`, `ProfilesController.effectiveConfig` | Partial: raw YAML edit/export and read-only effective preview/export merge global settings and the profile script without starting the core. Controller secrets are redacted in the preview and removed from effective copies/exports. YAML/script editors and effective preview support case-insensitive find with previous/next selection and scroll-to-match; other upstream editor tooling remains incomplete. |
| Profile standard extension (`profiles/extend/standard.dart`) | `ProfileSettingsDialog`, `standard_extension.dart`, `ConfigBuilder` | Implemented: each profile can store validated additional rules and an optional MATCH-TARGET; rules are applied before global added rules and subscription rules, with LAN/localhost/MATCH presets. The full upstream drag-and-drop rule library and extension-mode switcher remain outside the current scope. |
| Profile script extension (`profiles/extend/script.dart`) | Per-profile editor, shared script library; `ConfigBuilder` QuickJS | Implemented basic execution: enabled shared `main(config)` scripts run in library order, followed by the profile's own script. Failures identify the shared script name. Upstream script-selection and extension-mode interfaces still differ. |
| Custom profile builder (`profiles/custom/*`) | `ProfileBuilderView`, `profiles/builder` | Partial: five visual sections edit proxies, groups, proxy/rule providers and ordered rules. SS/VMess/VLESS/Trojan/Hysteria2/SOCKS5/HTTP forms, member/provider pickers and test options preserve unknown fields; advanced YAML handles unsupported types/options. One complete document is saved through the existing validated atomic profile-save/reload flow. Dedicated dialer controls, richer imports, icons and full upstream field coverage remain missing. |

## Connections, request history, DNS and logs

| FlClash surface | Cloudrift source | Status and remaining work |
| --- | --- | --- |
| Active connections/details/close one or all | `app/pages/connections` | Implemented: metadata/process/route search, totals sorting, close commands and copyable details. Upstream speed ranking and configurable table columns are missing. |
| Request history (`views/connection/requests.dart`) | `FeedView(dns: false)` | Partial: live bounded history, search, pause/resume, clear and full JSON details/copy. Upstream tracker columns, per-request traffic updates and keyword filter tooling need parity work. |
| DNS queries (`views/dns_queries.dart`) | `FeedView(dns: true)` | Partial: domain/type/answer summaries, search/pause/clear and full details. Typed upstream/initiator/cache/error/latency columns and configurable tables are missing. |
| Logs (`views/logs.dart`) | `app/pages/logs` | Implemented: level/search filters, pause/resume, clear, row/all copy and filtered native file export. Upstream automatic follow-to-end and presentation controls differ. |

## Configuration, resources and tools

| FlClash surface | Cloudrift source | Status and remaining work |
| --- | --- | --- |
| General ports/log level/test URL/start on launch | `settings/settings_view.dart` | Implemented for mixed port, log level, test URL/timeout, connect on launch, desktop launch at login and tray close preference. Separate inbound port/authentication controls and silent launch remain missing. |
| DNS/TUN/sniffer/NTP editors (`views/config/{dns,tun,sniffer,ntp}.dart`) | `StructuredConfigEditorView`, `config_editor` | Partial: common toggle/text/list/choice controls and complete YAML modes are reachable. Form edits preserve unknown fields; recursive overrides preserve sibling fields from the profile. Resetting a field inherits its profile value. Full upstream field coverage and presets remain missing. |
| Added rules and hosts | YAML editors via `SettingsController.saveYaml` | Partial: persisted and applied as actual overrides. Typed rule forms, templates, reorder and map-entry UI are missing. |
| External controller and authentication | Network controller switch/port and access dialog | Partial: loopback port editing and session-secret viewing/copying are implemented. Custom listen addresses, user-managed secret rotation and proxy authentication UI remain missing. |
| Privileged TUN helper | Network helper install/uninstall rows; `HelperClient` | Implemented in source for Windows/Linux with explicit confirmation before administrator authorization and errors shown in settings. Changes require the core to be stopped; native installation and TUN effects remain unverified. |
| Android access control (`views/access.dart`) | Network settings, `settings/access`, `AndroidInstalledApps` | Implemented in source: installed-app enumeration, lazy bounded icon loading, search, system/network/selected filters and batch selection, with a manual package-name fallback. Selected missing/hidden packages are retained. Enabled/mode/package lists reach native VPN state; device permission and VPN acceptance remain unverified. |
| Resource libraries (`config/custom_resources.dart`, `providers.dart`, `filters.dart`, `icon_sets.dart`) | `ResourceLibraryService`, Tools → Resource library, Profile Builder resource picker | Implemented: versioned reusable proxy/rule/regex/icon resources support URL, file and inline sources, manual refresh, enable/disable, validation, backup/restore and Profile Builder import/apply actions. Automatic refresh policies, remote conflict merging and full icon download caching remain missing. |
| Global scripts (`config/scripts.dart`) | `ScriptLibraryService`, Settings → Shared scripts, Profile settings | Implemented: local create/edit/delete, enable/disable and ordered execution, HTTPS import/manual refresh with bounded transfers, plus per-profile selection with legacy fallback to all enabled scripts. New or changed code remains disabled until reviewed and enabled. Versioned JSON is included in settings backups, unknown fields are preserved and corrupt data is retained for explicit recovery. Automatic refresh policies and per-profile script presets remain missing. |
| User-agent presets (`config/user_agents.dart`) | Raw profile YAML only | Missing as managed UI. |
| On-demand/network policy (`config/on_demand.dart`) | No equivalent | Missing. |
| Geo resource updates | `ProvidersView` geo actions | Partial: mmdb/geoip/geosite/asn update calls exist. Source URLs, loading policy and resource inspection UI differ. |
| Backup/WebDAV (`backup_and_restore.dart`) | `BackupView`, `BackupService` | Implemented basic validated ZIP export/import and WebDAV upload/download. Upstream restore strategy/selection and remote file management are missing; formats are Cloudrift-specific. |
| Appearance/font (`theme.dart`, `font_family.dart`) | `AppearanceView` | Partial: system/light/dark, pure black, accent presets, system/JetBrains Mono font choice and Chinese/English are implemented. Custom colors, additional fonts, text scale, navigation style, animation/glass/blur preferences and other locales are missing. |
| Desktop hotkeys (`hotkey.dart`) | Fixed navigation shortcuts | Partial: page shortcuts exist. Configurable global hotkey manager and start/stop/mode hotkeys are missing. |
| Tray/window/launch integration | `DesktopIntegrationService`, `DesktopStartup` | Partial: tray actions, show/close/minimize, teardown and launch-at-login controls exist in source. Silent launch is missing; native validation remains required. |
| Deep-link import | `LinkService`, `ProfileService.importUrl` | Partial: supported install-config links are handled with confirmation. Compatibility aliases and initial-link handling require platform checks. |
| About/licenses | `SettingsView.showAbout`, license registry | Implemented basic attribution/license display. Upstream update checker, diagnostics/developer/disclaimer surfaces are missing. |
| iOS | No native implementation | Unsupported; the reference snapshot does not provide an iOS runtime to migrate. |

## Completion criteria still outstanding

The most consequential remaining product gaps are complete custom-profile field/import coverage, the full upstream standard-extension rule library, freeform dashboard layout, complete structured network configuration, and broader platform acceptance testing. Common visual profile editing, per-profile standard rules and reusable resource libraries are available; advanced YAML covers additional fields without reproducing every upstream interface.

Native builds, widget checks, lifecycle/config/storage tests and source review must be recorded separately. A successful macOS preview does not verify Android VPN consent, desktop privilege escalation, TUN routing, proxy restoration, native file pickers, or interoperability with existing FlClash backups.
