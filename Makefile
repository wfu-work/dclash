# dclash Flutter 常用开发入口。
#
# 原生 hook 会在构建时生成 Rust / Go 产物；所有 build/test 目标都通过
# 工作区脚本串行执行，并使用独立 Cargo home，避免修改用户全局配置。

FLUTTER_HOME ?=
ifeq ($(origin FLUTTER),undefined)
FLUTTER := $(shell \
	if command -v flutter >/dev/null 2>&1; then command -v flutter; \
	elif [ -n "$(FLUTTER_HOME)" ] && [ -x "$(FLUTTER_HOME)/bin/flutter" ]; then printf '%s' "$(FLUTTER_HOME)/bin/flutter"; \
	elif [ -n "$$FLUTTER_HOME" ] && [ -x "$$FLUTTER_HOME/bin/flutter" ]; then printf '%s' "$$FLUTTER_HOME/bin/flutter"; \
	elif [ -x "$$HOME/Documents/applications/flutter/bin/flutter" ]; then printf '%s' "$$HOME/Documents/applications/flutter/bin/flutter"; \
	elif [ -x "$$HOME/Development/flutter/bin/flutter" ]; then printf '%s' "$$HOME/Development/flutter/bin/flutter"; \
	elif [ -x "$$HOME/development/flutter/bin/flutter" ]; then printf '%s' "$$HOME/development/flutter/bin/flutter"; \
	elif [ -x "$$HOME/.local/flutter/bin/flutter" ]; then printf '%s' "$$HOME/.local/flutter/bin/flutter"; \
	else printf '%s' flutter; fi)
endif

DART ?= dart
PYTHON ?= python3
DEVICE ?=
CARGO_HOME ?= .dart_tool/cargo-home
ANDROID_TARGET_PLATFORM ?= android-arm64
TEST_CONCURRENCY ?= 2
TEST_ARGS ?=
RUN_ARGS ?=
PREVIEW ?= false
DMG_DIR ?= build/releases
DMG_VOLUME_NAME ?= dclash
MACOS_ARCH ?= $(shell uname -m)

FLUTTER_DIR := $(dir $(FLUTTER))
FLUTTER_PATH = PATH="$(FLUTTER_DIR):$${PATH}"
CARGO_ARG = --isolated-cargo-home=$(CARGO_HOME)
PREVIEW_ARG = $(if $(filter true 1 yes,$(PREVIEW)),--dart-define=DC_PREVIEW=true,)

.DEFAULT_GOAL := help
.PHONY: help require-flutter get run preview dev doctor analyze format test check clean \
	icons core apk apk-debug apk-preview macos macos-release macos-preview linux windows \
	dmg verify-macos

require-flutter:
	@if { [ -f "$(FLUTTER)" ] && [ -x "$(FLUTTER)" ]; } || command -v "$(FLUTTER)" >/dev/null 2>&1; then \
		exit 0; \
	fi; \
	printf '未找到 Flutter SDK（需要 Flutter 3.44+）。请安装后执行：\n  make dev FLUTTER=/path/to/flutter/bin/flutter\n' >&2; \
	exit 127

get run preview dev doctor analyze format test clean icons core apk apk-debug apk-preview macos macos-release macos-preview linux windows dmg verify-macos: require-flutter

help: ## 显示命令说明（直接执行 make 也会显示）
	@printf 'dclash Flutter\n\n用法：make <命令> [参数=值]\n\n命令：\n'
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\n参数：\n  FLUTTER       Flutter 可执行文件，默认自动查找 PATH、FLUTTER_HOME 和常用安装目录\n  DART          Dart 可执行文件，默认 dart\n  DEVICE        run 时使用的设备 ID\n  PREVIEW       设为 true 为只读界面预览，不接管网络\n  CARGO_HOME    隔离 Cargo 目录，默认 .dart_tool/cargo-home\n  DMG_DIR       DMG 输出目录，默认 build/releases\n  DMG_VOLUME_NAME  DMG 卷名，默认 dclash\n  MACOS_ARCH    macOS 架构，默认本机；支持 arm64 或 x86_64\n  TEST_ARGS     追加给测试脚本的参数\n  RUN_ARGS      追加给 flutter run 的参数\n\n示例：\n  make get\n  make dev\n  make preview\n  make run DEVICE=emulator-5554\n  make apk-preview\n  make macos-preview\n  make dmg\n  make dmg DMG_DIR=/tmp/dclash-releases MACOS_ARCH=arm64\n  make check\n'

get: ## 安装 Flutter 依赖
	"$(FLUTTER)" pub get

run: ## 启动应用；未指定 DEVICE 时由 Flutter 选择
	"$(FLUTTER)" run $(if $(strip $(DEVICE)),-d "$(DEVICE)") $(PREVIEW_ARG) $(RUN_ARGS)

preview: PREVIEW=true
preview: ## 启动只读界面预览（DC_PREVIEW=true）
	$(MAKE) run PREVIEW=true DEVICE="$(DEVICE)" RUN_ARGS="$(RUN_ARGS)"

dev: ## 启动当前宿主的桌面调试版并支持热重载
	@case "$(OS):$$(uname -s 2>/dev/null)" in \
		*:Darwin) desktop=macos ;; \
		*:Linux) desktop=linux ;; \
		Windows_NT:*|*:MINGW*|*:MSYS*|*:CYGWIN*) desktop=windows ;; \
		*) printf '当前宿主没有可识别的桌面目标。\n' >&2; exit 1 ;; \
	esac; \
	"$(FLUTTER)" run -d "$$desktop" $(PREVIEW_ARG) $(RUN_ARGS)

doctor: ## 检查 Flutter 与原生工具链
	"$(FLUTTER)" doctor -v

analyze: ## 运行 Dart 静态分析
	"$(FLUTTER)" analyze --no-pub

format: ## 格式化 Dart 源码
	"$(DART)" format lib test tool

test: ## 运行单元和 Widget 测试（使用项目测试包装脚本）
	"$(DART)" tool/test.dart --no-pub --concurrency=$(TEST_CONCURRENCY) $(TEST_ARGS)

check: ## 串行执行格式化、静态分析和测试
	$(MAKE) format
	$(MAKE) analyze
	$(MAKE) test

clean: ## 清理 Flutter 构建缓存
	"$(FLUTTER)" clean

icons: ## 生成 dclash 各平台应用图标
	"$(PYTHON)" tool/generate_icons.py

core: ## 构建 Go / mihomo sidecar
	"$(DART)" tool/build_core.dart

apk: apk-debug ## 构建 Android ARM64 Debug APK（默认不接管网络）

apk-debug: ## 构建 Android Debug APK；使用隔离 Cargo home
	$(FLUTTER_PATH) "$(DART)" tool/build.dart apk $(CARGO_ARG) --debug --no-pub --target-platform=$(ANDROID_TARGET_PLATFORM) --split-per-abi $(PREVIEW_ARG)

apk-preview: ## 构建带 DC_PREVIEW=true 的 Android 预览 APK
	$(MAKE) apk-debug PREVIEW=true

macos: ## 构建 macOS Debug App
	$(FLUTTER_PATH) "$(DART)" tool/build_macos.dart $(CARGO_ARG) --debug --no-pub $(PREVIEW_ARG)

macos-release: ## 构建 macOS Release App
	FLUTTER_XCODE_ARCHS="$(MACOS_ARCH)" $(FLUTTER_PATH) "$(DART)" tool/build_macos.dart $(CARGO_ARG) --release --no-pub

macos-preview: ## 构建带 DC_PREVIEW=true 的 macOS 预览 App
	$(MAKE) macos PREVIEW=true

linux: ## 构建 Linux Debug 目录
	$(FLUTTER_PATH) "$(DART)" tool/build.dart linux $(CARGO_ARG) --debug --no-pub $(PREVIEW_ARG)

windows: ## 构建 Windows Debug 目录（需在 Windows 宿主执行）
	$(FLUTTER_PATH) "$(DART)" tool/build.dart windows $(CARGO_ARG) --debug --no-pub $(PREVIEW_ARG)

dmg: ## 构建 macOS Release App、DMG 安装包和 SHA-256 校验文件
	FLUTTER_BIN="$(FLUTTER)" DART_BIN="$(DART)" CARGO_HOME="$(CARGO_HOME)" MACOS_ARCH="$(MACOS_ARCH)" DMG_OUTPUT_DIR="$(DMG_DIR)" DMG_VOLUME_NAME="$(DMG_VOLUME_NAME)" ./script/package_macos_dmg.sh

verify-macos: ## 验证已构建 macOS App 的深度签名
	"$(DART)" tool/verify_macos_bundle.dart build/macos/Build/Products/Debug/dclash.app
