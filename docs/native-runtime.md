# Native runtime and build checks

Cloudrift uses the vendored Mihomo bridge in `core/` and the retained Rust IPC,
QuickJS and desktop plugins in `plugins/`. Upstream provenance and licenses are
recorded in `core/UPSTREAM.md` and `third_party/`.

## Build prerequisites

- Flutter 3.44 / Dart 3.12 and resolved application dependencies.
- Go 1.27 for the retained bridge and its Android gomobile binding.
- Rust 1.99.0. The Rust hook stages its crate under `.dart_tool/` and requests
  only the current target; it does not rewrite the checked-in toolchain file.
- Xcode and CocoaPods for macOS. The Xcode project targets macOS 12 or later;
  login items use ServiceManagement on macOS 13 or later.
- Android SDK 37 and the NDK selected in `android/gradle/libs.versions.toml`.
  Android currently keeps the Kotlin plugin compatibility flags required by
  retained plugins; AGP reports deprecation warnings for these flags.

The Rust native hook supports Android ARM/ARM64/x64, macOS ARM64/x64, Windows
ARM64/x64, and Linux ARM64/x64. iOS is unsupported. Cargo uses the machine's
registry settings, so a first native build can download a large configured
registry index as well as crates.

To use a task-local Cargo cache and skip registry overrides inherited from
ancestor directories, the Rust hook supports an opt-in isolated working
directory. It leaves the user's Cargo configuration unchanged:

```sh
dart tool/build_macos.dart --isolated-cargo-home=.dart_tool/cargo-home --debug --dart-define=DC_PREVIEW=true
```

This wrapper temporarily passes `cargo_home` and `cargo_isolated` through
`hooks.user_defines.rust_api`, then restores the pubspec. Native hooks strip
arbitrary environment variables, including `CARGO_HOME`; setting it only on the
Flutter command does not configure the hook. Run this wrapper serially with
other Flutter commands, including `tool/test.dart`. The selected Cargo home may
contain a `config.toml` with the developer's registry choice.

The general entry point accepts a Flutter build target. The existing macOS
entry point remains compatible. For an Android ARM64 debug APK, including the
Flutter bundle and Rust native assets:

```sh
dart tool/build.dart apk --isolated-cargo-home=.dart_tool/cargo-home --debug --no-pub --target-platform=android-arm64 --split-per-abi
```

This only builds an APK; it does not install or run it.
`--split-per-abi` keeps the final APK limited to ARM64, including transitive
plugin libraries. A target-platform setting alone can retain other ABIs from
prebuilt plugin dependencies.

## macOS development bundle signing

The macOS build wrappers verify the final bundle with
`codesign --verify --deep --strict` after Flutter finishes. An incremental
Flutter build can update and sign `App.framework` or a native asset framework
while leaving Xcode's older outer resource seal in place. In that case, the
wrapper independently verifies the nested code, then reseals only an existing
ad hoc Debug app. It preserves the signing identifier, entitlements,
requirements, flags and runtime metadata, and checks the resulting identity
and entitlements against their original values. It does not re-sign nested
frameworks or use a distribution certificate. Other verification failures
remain errors.

The final macOS build exercised this repair and passed the full signature
check. To perform a read-only verification of an existing artifact:

```sh
dart tool/verify_macos_bundle.dart build/macos/Build/Products/Debug/Cloudrift.app
```

## Commands

Run these from the application root:

```sh
flutter pub get
dart tool/build_core.dart
flutter build macos --debug --dart-define=DC_PREVIEW=true
dart tool/test.dart --no-pub test/core
dart analyze lib/platform lib/services/core_service.dart test/core
```

`tool/build_core.dart` is a direct Dart entry point so it can build the sidecar
before Flutter evaluates native hooks. `tool/test.dart` temporarily disables
the setup and Rust asset builds for unit/widget tests, then restores the
pubspec. Run it directly with `dart`, and do not run it concurrently with a
Flutter build in this checkout.

The Android native modules can be checked separately from the Flutter bundle:

```sh
cd android
./gradlew :common:compileDebugKotlin :service:compileDebugKotlin :core:compileDebugKotlin -Ptarget-platform=android-arm64 --console=plain
```

This command builds the gomobile core binding. It does not by itself prove
that the complete APK, Flutter native assets, or application resources build.

The Android application Kotlin/Java and resource check, without a Flutter
bundle/native-assets build, is:

```sh
cd android
./gradlew :app:compileDebugKotlin :app:compileDebugJavaWithJavac :app:processDebugResources -x :app:compileFlutterBuildDebug -Ptarget-platform=android-arm64 --console=plain
```

For an explicitly authorized sidecar smoke check on macOS:

```sh
python3 tool/smoke_core.py libclash/macos/DClashCore
```

This launches only the named task-built binary with a temporary private home
and IPC socket. It exercises version/init/setup/traffic/invalid-config/shutdown
RPC, never calls `startListener`, disables TUN, DNS, NTP and all inbound ports,
and checks the owned PID has no Internet sockets. Its cleanup addresses only
that child process. This does not test actual proxy or VPN traffic.

## Runtime boundaries

`CoreService.initialize()` does not load or start the core. Explicit connect
creates one lifecycle owner, a private generated configuration and one native
session. Desktop teardown addresses the owned process/session, and a failed
cleanup can be retried. Rust library initialization is shared by script
evaluation and IPC without starting a core process.

Android uses `com.cloudrift.dclash/service` and `com.cloudrift.dclash/core`, VPN
permission and native service state. Desktop IPC uses the DClash socket/pipe
namespace. macOS TUN requests administrator authorization for the owned core;
Linux/Windows TUN uses the DClash privileged helper with protocol, installation
path, binary hash and process ownership checks. Helper installation is an
explicit action and never occurs during initialization.

The macOS bundle embeds/signs `DClashCore` in `Contents/MacOS`. Linux CMake
installs the core, helper and manifest under the bundle library directory;
Windows installs them beside the runner. Linux/Windows packaging and runtime
behavior still need validation on their respective hosts.

`DC_PREVIEW=true` uses labeled fixtures and rejects core/network mutations.
Builds, analysis and isolated tests do not validate actual VPN consent, TUN
routes, privileged helper installation, login items, system proxy restoration,
or interaction with another installed proxy application. These require
separate acceptance checks on the target platforms.

## Verification captured in this workspace

| Check | Observed result |
| --- | --- |
| `dart tool/test.dart --no-pub test/core` | 21 tests passed, including lifecycle, invalid-profile retention, maintenance locking, startup mode changes and proxy cleanup retries. |
| `dart tool/test.dart --no-pub plugins/proxy/test` | 26 tests passed. Host proxy settings were not changed. |
| Go bridge IPC/configuration test subset with `CGO_ENABLED=0` | Passed. Disabling CGO is required to include the desktop IPC test file. |
| Temporary-home sidecar smoke | Passed, including invalid configuration retention and owned-process exit. No listeners or Internet sockets were opened. |
| Android native modules and application Kotlin/Java/resources | Passed for Android ARM64. |
| Complete Android ARM64 debug APK | Passed after the latest application fixes. `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` contains only `arm64-v8a`, including Go (`libclash.so`), Rust (`librust_api.so`), Flutter and the Dart kernel. APK v2 signature verification passed. Metadata is `com.cloudrift.dclash`, label `云渡 Cloudrift`, minSdk 24, targetSdk 36. No APK was installed or run. |
| macOS debug build with `DC_PREVIEW=true` | Passed. `build/macos/Build/Products/Debug/Cloudrift.app` contains `Contents/MacOS/DClashCore` and `rust_api.framework`; `codesign --verify --deep --strict` passed. An isolated preview UI launch was also performed, using fixtures with native mutations blocked. |

The final complete Android build log is
`build/verification/android-arm64-debug-apk-final.log` (the first native build
is in `build/verification/android-arm64-debug-apk.log`). The final macOS rebuild log is
`build/verification/macos-preview-final.log` (the earlier native build is in
`build/verification/macos-preview.log`). The preview artifact validates
compilation, bundling and the isolated UI; actual VPN/proxy/helper behavior and
Linux/Windows builds remain outside these checks.
