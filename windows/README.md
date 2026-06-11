# SilentShot · 静默后台热键截图

真·无窗口的 Windows 后台截图小工具。按下 `Ctrl+Alt+S` 即静默截下整个屏幕（含多显示器），
**无遮罩、无通知、无声音、无任何窗口闪现** —— 投屏 / 会议 / 录屏中也不会被察觉。

> 编译为 **GUI 子系统（winexe）** 进程，根本不分配控制台窗口，所以屏幕上没有任何可被误关的窗口。
> 要停止它，只能在「任务管理器」里结束 `SilentShot.exe`。

## 特性

- **静默全屏截图**：`Ctrl+Alt+S` 一键截取整个虚拟屏幕（自动覆盖所有显示器），保存为 PNG。
- **零界面**：隐藏窗体（`Opacity=0`、不在任务栏、移到屏外），消息循环只为接收全局热键。
- **DPI 感知**：高分屏下截图不糊（`SetProcessDPIAware`）。
- **单实例守卫**：用命名 Mutex 防止重复启动抢占同一热键。
- **轻量**：编译产物仅约 6.5 KB，纯 .NET Framework，无第三方依赖。

截图保存到：`我的图片\Screenshots\shot_yyyyMMdd_HHmmss.png`
运行日志写到：`我的图片\Screenshots\_listener.log`

> ⚠️ 受 DRM 硬件保护的内容（如 Netflix 等）会截成黑块 —— 这是显卡层面的保护，软件无法绕过。

## 安装与使用

### 方式一：直接下载（推荐）

到 [Releases](../../releases) 页下载 `SilentShot.exe`，双击运行即可。运行后没有任何窗口，
直接按 `Ctrl+Alt+S` 试一下，截图会出现在 `我的图片\Screenshots\` 里。

### 方式二：自行编译

需要 Windows + .NET Framework 4.x（系统自带）。

```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```

脚本会用系统自带的 `csc.exe` 以 `/target:winexe` 把 `SilentShot.cs` 编译成 `SilentShot.exe`。

## 设为开机自启

把 `SilentShot.exe` 的快捷方式放进启动文件夹即可（按 `Win+R` 输入 `shell:startup` 打开）：

```powershell
$exe = "C:\path\to\SilentShot.exe"
$startup = [Environment]::GetFolderPath('Startup')
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut((Join-Path $startup 'SilentShot.lnk'))
$lnk.TargetPath = $exe
$lnk.Save()
```

## 如何停止

进程无窗口，正常退出方式是「任务管理器 → 找到 `SilentShot.exe` → 结束任务」，
或 PowerShell：`Stop-Process -Name SilentShot`。

## 工作原理

| 环节 | 实现 |
| --- | --- |
| 全局热键 | `RegisterHotKey` 注册 `Ctrl+Alt+S`，在隐藏窗体的 `WndProc` 里收 `WM_HOTKEY` |
| 截图 | `Graphics.CopyFromScreen` 抓 `SystemInformation.VirtualScreen`（多屏合并区域）|
| 隐身 | `FormBorderStyle=None` + `Opacity=0` + `ShowInTaskbar=false` + 移到屏外 + `SetVisibleCore(false)` |
| 单实例 | 命名 `Mutex`，第二个实例启动即退出 |

源码只有一个文件 [`SilentShot.cs`](SilentShot.cs)，约 90 行，易于审计。

## 许可证

MIT
