# SilentShot · macOS · 静默后台热键截图

macOS 版的静默截图小工具。按下 `⌃⌥S`（Ctrl+Option+S）即静默截下整个屏幕（含多显示器），
**无快门声、无闪屏、无遮罩** —— 投屏 / 会议 / 录屏中也不会被察觉。和 Windows 版同源，并额外支持
**可配置热键、可改保存位置、菜单栏图标 + 偏好窗口 + HTML 设置页**。

> 以菜单栏 App 形式运行（无 Dock 图标）。菜单栏图标可隐藏，做到完全隐身；隐藏后再次打开 App
> 会自动弹出偏好设置。要停止它，点菜单栏图标 →「退出」，或 `pkill -f SilentShot`。

## 特性

- **静默全屏截图**：`⌃⌥S` 一键截取，支持多显示器（每屏一张），保存为 PNG / JPG。
- **进程内截图**：用 ScreenCaptureKit 在本进程截图，**SilentShot 自己**成为「屏幕录制」授权对象
  （按名字出现在系统设置里，授权可持久），截图无声无闪。
- **不需要「辅助功能」权限**：全局热键用 Carbon `RegisterEventHotKey`，唯一需要的系统权限是
  **屏幕录制**。
- **可配置**：热键、保存目录、文件名前缀、图片格式、是否截取所有显示器、提示音、菜单栏图标、
  开机自启 —— 都能在偏好窗口或 HTML 设置页里改。
- **单实例守卫**：重复启动不会抢占同一热键（再次启动只会弹出偏好设置）。

截图保存到：`~/Pictures/Screenshots/shot_yyyyMMdd_HHmmss.png`（多屏追加 `_1`、`_2`）
运行日志写到：`~/Pictures/Screenshots/_listener.log`

## 安装与使用

需要 macOS 14+ 和 Xcode 命令行工具（`swiftc`，`xcode-select --install` 即可）。

```sh
cd macos
./install.sh        # 编译 → 安装到 ~/Applications → 启动
```

或只编译、手动运行：

```sh
./build.sh
open SilentShot.app
```

### 授予屏幕录制权限（必需，仅一次）

首次按热键截图时，系统会弹出「屏幕录制」授权请求。到
**系统设置 → 隐私与安全性 → 屏幕录制**，勾选 **SilentShot**，按提示重新打开 App 即可。
（无需「辅助功能 / 输入监控」权限。）

### 截图

- 按默认热键 `⌃⌥S`，或点菜单栏相机图标 →「立即截图」。
- 截图出现在 `~/Pictures/Screenshots/`。

## 配置

三种方式，改的是同一份配置 `~/.config/silentshot/config.json`：

1. **偏好窗口**：菜单栏图标 →「偏好设置…」。改动实时生效（含重注册热键）。
2. **HTML 设置页**：菜单栏 →「打开设置网页…」（或直接用浏览器打开 `settings.html`），
   填好后「下载 config.json」存到 `~/.config/silentshot/config.json`，再点菜单「重新载入配置」。
3. **手改 JSON**：直接编辑 `~/.config/silentshot/config.json`，菜单「重新载入配置」生效。

```json
{
  "hotkey": "ctrl+option+s",
  "saveDirectory": "~/Pictures/Screenshots",
  "filenamePrefix": "shot",
  "imageFormat": "png",
  "captureAllDisplays": false,
  "playShutterSound": false,
  "showMenuBarIcon": true,
  "launchAtLogin": false
}
```

- `hotkey`：人类可读串，如 `ctrl+option+s` / `cmd+shift+4` / `ctrl+option+f5`。修饰键
  `ctrl` `option`(=alt) `shift` `cmd`，加一个主键。
- `showMenuBarIcon: false` 可完全隐藏图标；隐藏后再次 `open SilentShot.app` 会弹出偏好设置。

## 开机自启

在偏好窗口勾选「开机自启」（内部用 `SMAppService`，会在系统设置 → 通用 → 登录项里出现）。
不要再额外配 LaunchAgent，避免两套自启机制冲突。

## 如何停止

菜单栏图标 →「退出 SilentShot」，或：

```sh
pkill -f "SilentShot.app/Contents/MacOS/SilentShot"
```

## 卸载

```sh
cd macos && ./uninstall.sh
```

会退出并删除 `~/Applications/SilentShot.app`、复位屏幕录制授权。配置文件如需清理：
`rm -rf ~/.config/silentshot`。

## 局限（请知悉）

- **macOS 15+ 周期提醒**：持有屏幕录制权限的 App，系统会**周期性**弹「SilentShot 正在录制你的屏幕」
  提醒，**第三方无法关闭**；SilentShot 也会**长期**出现在「屏幕录制」列表里。这是 macOS 的隐私机制，
  类比 Windows 版「DRM 黑屏」那条不可绕过的限制。
- **DRM / 受保护画面**：部分受保护的视频/安全输入界面会截成黑块 —— 系统层面的保护，软件无法绕过。
- **签名与授权持久性**：默认 ad-hoc 签名零配置即可用，但**重新编译后可能需要重新授权屏幕录制**。
  想要跨重建稳定，可在「钥匙串访问 → 证书助理 → 创建证书」建一个类型为「代码签名」、名为
  `SilentShot Self-Signed` 的自签证书，`build.sh` 会自动用它签名（也可设
  `SILENTSHOT_SIGN_IDENTITY=<证书名>`）。复位授权：`tccutil reset ScreenCapture com.silentshot.mac`。

## 工作原理

| 环节 | 实现 |
| --- | --- |
| 全局热键 | Carbon `RegisterEventHotKey` + `InstallEventHandler`（**不需要辅助功能权限**） |
| 截图 | ScreenCaptureKit `SCScreenshotManager.captureImage`，按 `CGGetActiveDisplayList` 枚举每个显示器，原生分辨率 |
| 隐身 | `NSApplication.setActivationPolicy(.accessory)`（无 Dock 图标）+ 菜单栏图标可隐藏 + 截图无声无闪 |
| 配置 | `~/.config/silentshot/config.json`，偏好窗口 / HTML 设置页 / 手改 三种入口 |
| 开机自启 | `SMAppService.mainApp` |
| 单实例 | `NSRunningApplication` 检查 + `LSMultipleInstancesProhibited` |

源码只有一个文件 [`SilentShot.swift`](SilentShot.swift)，易于审计。

## 许可证

MIT（见仓库根目录 [`LICENSE`](../LICENSE)）
