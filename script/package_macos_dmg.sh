#!/usr/bin/env bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"

if [[ "$(uname -s)" != Darwin ]]; then
  printf 'DMG 打包需要在 macOS 上执行。\n' >&2
  exit 1
fi

TASK_FLUTTER="${FLUTTER_BIN:-flutter}"
TASK_DART="${DART_BIN:-dart}"
if [[ "$TASK_FLUTTER" == */* ]]; then
  [[ -x "$TASK_FLUTTER" ]] || {
    printf '找不到 Flutter：%s\n' "$TASK_FLUTTER" >&2
    exit 1
  }
  TASK_FLUTTER_DIR="$(cd "$(dirname "$TASK_FLUTTER")" && pwd)"
  export PATH="$TASK_FLUTTER_DIR:$PATH"
elif ! command -v "$TASK_FLUTTER" >/dev/null 2>&1; then
  printf '找不到 Flutter，请设置 make dmg FLUTTER=/path/to/flutter。\n' >&2
  exit 1
fi
command -v "$TASK_DART" >/dev/null 2>&1 || {
  printf '找不到 Dart，请设置 make dmg DART=/path/to/dart。\n' >&2
  exit 1
}

TASK_ARCH="${MACOS_ARCH:-$(uname -m)}"
case "$TASK_ARCH" in
  arm64|x86_64) ;;
  *) printf 'MACOS_ARCH 只支持 arm64 或 x86_64。\n' >&2; exit 1 ;;
esac
export FLUTTER_XCODE_ARCHS="$TASK_ARCH"

TASK_CARGO_HOME="${CARGO_HOME:-.dart_tool/cargo-home}"
TASK_BUILD_ARGS=(
  tool/build_macos.dart
  "--isolated-cargo-home=$TASK_CARGO_HOME"
  --release
  --no-pub
)
TASK_APP="$TASK_ROOT/build/macos/Build/Products/Release/dclash.app"

# Release 包每次重新生成，避免 Flutter 增量产物与 Xcode 签名状态不一致。
rm -rf "$TASK_APP"
"$TASK_DART" "${TASK_BUILD_ARGS[@]}"

TASK_PLIST="$TASK_APP/Contents/Info.plist"
if [[ ! -f "$TASK_PLIST" ]]; then
  printf '找不到 Release 应用：%s\n' "$TASK_APP" >&2
  exit 1
fi

TASK_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TASK_PLIST")"
if [[ ! -x "$TASK_APP/Contents/MacOS/$TASK_EXECUTABLE" ]]; then
  printf 'Release 应用缺少可执行文件。\n' >&2
  exit 1
fi
/usr/bin/lipo "$TASK_APP/Contents/MacOS/$TASK_EXECUTABLE" -verify_arch "$TASK_ARCH"
/usr/bin/codesign --verify --deep --strict "$TASK_APP"

TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_PLIST")"
TASK_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TASK_PLIST")"
TASK_VERSION_LABEL="$TASK_VERSION"
if [[ -n "$TASK_BUILD" && "$TASK_BUILD" != "$TASK_VERSION" ]]; then
  TASK_VERSION_LABEL="$TASK_VERSION+$TASK_BUILD"
fi
TASK_FILENAME="dclash-$TASK_VERSION_LABEL-macos-$TASK_ARCH.dmg"
TASK_OUTPUT_DIR="${DMG_OUTPUT_DIR:-build/releases}"
mkdir -p "$TASK_OUTPUT_DIR"
TASK_OUTPUT_DIR="$(cd "$TASK_OUTPUT_DIR" && pwd)"

TASK_STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dclash-dmg.XXXXXX")"
trap 'rm -rf "$TASK_STAGE_ROOT"' EXIT
mkdir "$TASK_STAGE_ROOT/contents"
/usr/bin/ditto "$TASK_APP" "$TASK_STAGE_ROOT/contents/dclash.app"
ln -s /Applications "$TASK_STAGE_ROOT/contents/Applications"

if /usr/sbin/diskutil image create from --help >/dev/null 2>&1; then
  /usr/sbin/diskutil image create from \
    --volumeName "${DMG_VOLUME_NAME:-dclash}" \
    --format UDZO \
    "$TASK_STAGE_ROOT/contents" "$TASK_STAGE_ROOT/package.dmg"
else
  /usr/bin/hdiutil create \
    -volname "${DMG_VOLUME_NAME:-dclash}" \
    -srcfolder "$TASK_STAGE_ROOT/contents" \
    -format UDZO \
    "$TASK_STAGE_ROOT/package.dmg"
fi
/usr/bin/hdiutil verify "$TASK_STAGE_ROOT/package.dmg"
mv -f "$TASK_STAGE_ROOT/package.dmg" "$TASK_OUTPUT_DIR/$TASK_FILENAME"
(
  cd "$TASK_OUTPUT_DIR"
  /usr/bin/shasum -a 256 "$TASK_FILENAME" > "$TASK_FILENAME.sha256"
)

printf '\nDMG：%s/%s\n校验文件：%s/%s.sha256\n' \
  "$TASK_OUTPUT_DIR" "$TASK_FILENAME" "$TASK_OUTPUT_DIR" "$TASK_FILENAME"
