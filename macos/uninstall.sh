#!/bin/sh
# 退出并卸载 SilentShot。
set -eu

DEST="$HOME/Applications/SilentShot.app"
BUNDLE_ID="com.silentshot.mac"

# 退出运行中的实例（先尝试通过 SMAppService 注销登录项，再删 App）。
pkill -f "SilentShot.app/Contents/MacOS/SilentShot" 2>/dev/null || true

rm -rf "$DEST"
echo "已删除: $DEST"

# 复位屏幕录制授权，避免残留条目。
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
echo "已复位屏幕录制授权。"

cat <<'NOTE'

可选的彻底清理：
  - 配置文件:  rm -rf ~/.config/silentshot
  - 若「系统设置 → 通用 → 登录项」里仍有 SilentShot 残留条目，手动移除即可。
NOTE
