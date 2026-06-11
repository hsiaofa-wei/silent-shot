# SilentShot · 静默后台热键截图

一个跨平台的「无界面、后台、热键触发」截图小工具。一键静默截下整个屏幕（含多显示器），
**无遮罩、无通知、无声音、无窗口闪现** —— 投屏 / 会议 / 录屏中也不会被察觉。

| 平台 | 默认热键 | 说明 | 实现 |
| --- | --- | --- | --- |
| **Windows** | `Ctrl+Alt+S` | [windows/README](windows/README.md) | 单文件 C#（winexe），无窗口 |
| **macOS** | `⌃⌥S` | [macos/README](macos/README.md) | 单文件 Swift 菜单栏 App，可配置 + GUI/HTML |

## 共同理念

- **静默**：截图不发声、不闪屏、不弹通知、不抢焦点。
- **后台**：常驻进程只为接收全局热键；Windows 版无任何窗口，macOS 版可隐藏菜单栏图标。
- **热键驱动**：按一下就截全屏，存到「图片」目录，文件名带时间戳。
- **诚实**：受 DRM / 硬件保护的画面会截成黑块，软件无法绕过；macOS 15+ 还会周期性提醒
  「正在录制屏幕」（系统机制，无法关闭）。详见各平台 README 的「局限」。

## 快速开始

**Windows**（系统自带 .NET Framework 4.x）：

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File build.ps1   # 生成 SilentShot.exe
```

**macOS**（需要 macOS 14+ 和 `swiftc`）：

```sh
cd macos
./install.sh        # 编译 → 安装到 ~/Applications → 启动
```

macOS 版额外支持**可配置热键 / 保存位置**，并提供**菜单栏偏好窗口**与**HTML 设置页**两套配置界面。

## 许可证

MIT（见 [LICENSE](LICENSE)）
