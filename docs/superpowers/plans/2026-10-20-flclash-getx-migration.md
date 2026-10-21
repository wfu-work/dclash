# Cloudrift FlClash GetX Migration Implementation Plan

**Goal:** Implement a real cross-platform Flutter GetX proxy client matching FlClash feature surfaces, structured after Termax.
**Architecture:** View/controller/binding presentation, permanent GetX services, repository persistence, domain models, native platform adapters. Reuse attributed Go/native modules without adopting Riverpod.
**Tech stack:** Flutter 3.44+, Dart 3.12+, GetX 4, Go mihomo, Kotlin, Rust IPC/QuickJS.
**Spec:** ../../architecture.md

## Global constraints
- Work only inside dclash-flutter; FlClash and Termax are read-only.
- No mock network state in normal builds. Explicit preview mode is isolated from the host network.
- Keep GPL-3.0 attribution. Persist settings before publishing. No credentials in logs.
- Feature folders follow Termax conventions; shared UI components do not own domain logic.

## Initial migration tasks
- [x] Foundation: project, immutable contracts, settings, translations, theme and widgets; initialize with GetMaterialApp and scoped bindings.
- [x] Profile subsystem: atomic local repository, URL/file/custom imports, validation, updates and backup/WebDAV; test invalid and malicious imports.
- [x] Core subsystem: attributed native modules, IPC/RPC and mobile channels, authoritative lifecycle, monitoring, provider/delay operations; test transport and rapid intents.
- [x] Feature interfaces: proxies, profiles, connection/request/DNS feeds, logs and configuration tools, using shared controls and real services.
- [x] Integration: dashboard, routing/bindings, settings and backup tools, desktop shell, appearance and adaptive layouts.
- [x] Verification: format, pub get, analyze and tests, native builds, explicit offline UI preview at desktop/mobile sizes; document platform gaps precisely.

These checkboxes record the initial migration deliverables, not complete FlClash parity. See ../../feature-parity.md for unimplemented controls and behavior, and ../../verification.md for observed checks and native acceptance limits. The upstream application update checker is not implemented.
