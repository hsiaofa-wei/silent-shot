本仓库基于上游跨平台项目裁剪并拓展，**仅面向 Windows**。

| 组件 | 说明 |
| --- | --- |
| **[windows/](windows/)** | 静默截图主程序（单文件 C#，`winexe` 无窗口） |
| **[shot-board/](shot-board/)** | 局域网看板：手机浏览器实时查看最新截图（纯 Python 标准库） |

---

## 相对原项目做了什么

| 变更 | 说明 |
| --- | --- |
| **去掉 macOS** | 移除 Swift 菜单栏 App、安装脚本与 HTML 设置页；仓库只保留 Windows 路径 |
| **Windows 拓宽** | 在原有 `Ctrl+Alt+S` 全屏截图之外，增加 **Alt + 对角双击** 的静默区域截图（无遮罩） |
| **shot-board** | 新增局域网 HTTP 看板，手机浏览器跟拍最新截图与历史缩略图，图片不进手机相册 |

截图仍保存到：`我的图片\Screenshots\shot_yyyyMMdd_HHmmss.png`  
运行日志：`我的图片\Screenshots\_listener.log`

> 受 DRM 硬件保护的内容（如 Netflix）会截成黑块，软件无法绕过。

---

## 截图操作

| 操作 | 效果 |
| --- | --- |
| **`Ctrl+Alt+S`** | 静默截取整个虚拟屏幕（含多显示器） |
| **按住 `Alt`，对角双击两次** | 区域截图：起点对角双击一下，终点对角再双击一下，截取对角线矩形 |

特性要点：零界面（隐藏窗体 + 全局热键 / 鼠标钩子）、DPI 感知、单实例 Mutex、纯 .NET Framework、无第三方依赖。

---

## 快速开始

### 1. 编译并运行截图程序

需要 Windows + .NET Framework 4.x（系统自带）。

**编译：**

- cd 项目所在目录
- powershell -ExecutionPolicy Bypass -File build.ps1（生成 SilentShot.exe）

**启动：**

- .\SilentShot.exe（或双击SilentShot.exe）


**停止：**

- 任务管理器结束 `SilentShot.exe`
- Stop-Process -Name SilentShot
- taskkill /IM SilentShot.exe /F



### 手机看板 shot-board（可选）

电脑与手机在同一局域网。先保证 `SilentShot` 在跑并已有截图，再：

- cd shot-board
- python shot_board.py


终端会打印本机 IP，用手机浏览器打开即可。默认监视 `我的图片\Screenshots`，端口 `8765`。结束服务：`Ctrl+C`。

可选参数：

- dir   截图目录（默认 Pictures\Screenshots）
- port  端口（默认 8765）
- host  监听地址（默认 0.0.0.0）


需要 Python 3.8+，仅用标准库，无第三方依赖。


## 许可证

MIT（见 [LICENSE](LICENSE)）
