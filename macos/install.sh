#!/bin/sh
# 构建并安装 SilentShot 到 ~/Applications，然后启动一次（触发屏幕录制授权弹窗）。
#
# 注意：本脚本【不】安装 LaunchAgent。开机自启请在 App 偏好设置里勾选「开机自启」
# （内部用 SMAppService），避免两套自启机制抢同一热键。
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP="$ROOT_DIR/SilentShot.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/SilentShot.app"

sh "$ROOT_DIR/build.sh" "$@"

# 先退掉可能在跑的旧实例，再覆盖安装。
pkill -f "SilentShot.app/Contents/MacOS/SilentShot" 2>/dev/null || true
sleep 1

mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo "已安装到: $DEST"
open "$DEST"

cat <<'NOTE'

下一步：
  1. 首次按热键截图时（或刚启动时），系统会弹出「屏幕录制」授权——请允许。
     之后到「系统设置 → 隐私与安全性 → 屏幕录制」确认 SilentShot 已勾选。
  2. 默认热键 ⌃⌥S（Ctrl+Option+S）。点菜单栏相机图标 →「偏好设置…」可改热键、保存位置等。
  3. 想隐藏菜单栏图标：偏好设置里取消「在菜单栏显示图标」。隐藏后再次打开 App 即可重新弹出偏好设置。
NOTE
