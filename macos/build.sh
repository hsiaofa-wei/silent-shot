#!/bin/sh
# 把 SilentShot.swift 编译成菜单栏 App（SilentShot.app）。
#
# 关键点：
#   - 进程内截图，所以「屏幕录制」TCC 授权会算在本 App 名下（按名字出现在系统设置里）。
#   - 默认 ad-hoc 签名（零配置）。但纯 ad-hoc 每次重建都会让 TCC 重置 —— 源码没变就跳过重建/重签。
#     想要跨重建稳定的授权，可在钥匙串里建一个名为「SilentShot Self-Signed」的代码签名证书，
#     或设 SILENTSHOT_SIGN_IDENTITY=<证书名> 后再跑本脚本。
# 用法： ./build.sh [--force]
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$ROOT_DIR/SilentShot.swift"
SETTINGS="$ROOT_DIR/settings.html"
APP="$ROOT_DIR/SilentShot.app"
BIN="$APP/Contents/MacOS/SilentShot"
BUNDLE_ID="com.silentshot.mac"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

needs_build() {
    [ "$FORCE" -eq 1 ] && return 0
    [ ! -f "$BIN" ] && return 0
    [ "$SRC" -nt "$BIN" ] && return 0
    [ -f "$SETTINGS" ] && [ "$SETTINGS" -nt "$BIN" ] && return 0
    [ "$0" -nt "$BIN" ] && return 0
    return 1
}

if ! needs_build; then
    echo "✅ 无改动，跳过重建（保持已有授权）。要强制重建用 ./build.sh --force"
    echo "   App: $APP"
    exit 0
fi

echo "编译: $SRC"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# 部署目标 macOS 14（ScreenCaptureKit 的 SCScreenshotManager 需要 14+）。
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" "$SRC" -o "$BIN"

# settings.html 放进 App 包，供菜单「打开设置网页…」使用。
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$APP/Contents/Resources/settings.html"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>SilentShot</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleName</key>
	<string>SilentShot</string>
	<key>CFBundleDisplayName</key>
	<string>SilentShot</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>LSMultipleInstancesProhibited</key>
	<true/>
	<key>NSScreenCaptureUsageDescription</key>
	<string>SilentShot 需要屏幕录制权限来截屏。</string>
</dict>
</plist>
PLIST

if [ -n "${SILENTSHOT_SIGN_IDENTITY:-}" ]; then
    IDENTITY="$SILENTSHOT_SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "SilentShot Self-Signed"; then
    IDENTITY="SilentShot Self-Signed"
else
    IDENTITY="-"
fi

codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || codesign --force --sign "$IDENTITY" "$APP"
if [ "$IDENTITY" = "-" ]; then
    echo "🔏 已 ad-hoc 签名（重建后可能需要重新授权屏幕录制）。"
else
    echo "🔏 已用「$IDENTITY」签名（授权可跨重建保持）。"
fi

echo "✅ 构建完成: $APP"
echo "   双击运行，或： open \"$APP\""
