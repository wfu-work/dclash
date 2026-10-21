DClash core derives from FlClash v0.9.1's Go bridge and native build harness.
The upstream license is preserved in ../third_party/FlClash-LICENSE.

Clash.Meta is the chen08209/Clash.Meta fork at commit
8380d0e7462f061a964323e9bf3129a236fcc5d5 (FlClash branch), retrieved from
https://github.com/chen08209/Clash.Meta . Its GPL-3.0 license remains in
Clash.Meta/LICENSE. The pinned source is vendored to keep offline builds
independent of a missing Git submodule.

Build from the application root with `dart tool/build_core.dart`; Flutter's
setup build hook also compiles the sidecar. The macOS Xcode build embeds and
signs DClashCore in Contents/MacOS. Linux and Windows CMake bundles install the
core, helper, and SHA256 manifest into the bundle's executable library directory.
No build command starts the core, VPN, system proxy, or helper service.
