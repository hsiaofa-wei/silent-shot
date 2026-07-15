// SilentShot —— 真·无窗口后台截图程序（GUI 子系统，编译为 winexe）。
//
// 区域截图（静默，无遮罩/通知/声音）：
//   按住 Alt，在起点对角双击一下，再在终点对角双击一下，截取对角线矩形。
// 全屏截图：
//   Ctrl+Alt+S —— 静默截整个虚拟屏幕（含多显示器）。
//
// DRM 保护内容（Netflix 等）会截成黑块，硬件保护非软件可绕。
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public class HotkeyCatcher : Form {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] static extern uint GetDoubleClickTime();
    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string lpModuleName);

    delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int x, y; }

    [StructLayout(LayoutKind.Sequential)]
    struct MSLLHOOKSTRUCT {
        public POINT pt;
        public uint mouseData, flags, time;
        public IntPtr dwExtraInfo;
    }

    const int WM_HOTKEY = 0x0312;
    const int WM_LBUTTONDOWN = 0x0201;
    const int WH_MOUSE_LL = 14;
    const int HOTKEY_ID = 0xB001;
    const uint MOD_CTRL_ALT = 0x0002 | 0x0001;
    const uint VK_S = 0x53;
    const int VK_MENU = 0x12;          // Alt
    const int SM_CXDOUBLECLK = 36;
    const int SM_CYDOUBLECLK = 37;

    string outDir;
    string logFile;

    IntPtr mouseHook = IntPtr.Zero;
    LowLevelMouseProc mouseProc;       // 必须保活，否则委托被 GC 后钩子失效
    Point? cornerA;
    Point lastDown;
    int lastDownTick;
    bool lastDownValid;

    void Log(string msg) {
        try { File.AppendAllText(logFile, DateTime.Now.ToString("HH:mm:ss") + " " + msg + "\r\n"); } catch {}
    }

    public HotkeyCatcher(string dir) {
        outDir = dir;
        if (!Directory.Exists(outDir)) Directory.CreateDirectory(outDir);
        logFile = Path.Combine(dir, "_listener.log");
        SetProcessDPIAware();
        this.FormBorderStyle = FormBorderStyle.None;
        this.ShowInTaskbar = false;
        this.Opacity = 0;
        this.Size = new Size(0, 0);
        this.StartPosition = FormStartPosition.Manual;
        this.Location = new Point(-32000, -32000);

        bool ok = RegisterHotKey(this.Handle, HOTKEY_ID, MOD_CTRL_ALT, VK_S);
        Log(ok ? "STARTED hotkey Ctrl+Alt+S (fullscreen)" : "ERROR hotkey register failed");

        mouseProc = MouseHookCallback;
        using (var cur = System.Diagnostics.Process.GetCurrentProcess())
        using (var mod = cur.MainModule) {
            mouseHook = SetWindowsHookEx(WH_MOUSE_LL, mouseProc, GetModuleHandle(mod.ModuleName), 0);
        }
        Log(mouseHook != IntPtr.Zero
            ? "STARTED Alt+double-click region capture armed"
            : "ERROR mouse hook failed");
    }

    IntPtr MouseHookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && wParam == (IntPtr)WM_LBUTTONDOWN) {
            var info = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
            OnLeftDown(new Point(info.pt.x, info.pt.y));
        }
        return CallNextHookEx(mouseHook, nCode, wParam, lParam);
    }

    bool AltDown() {
        return (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
    }

    void OnLeftDown(Point pt) {
        int now = Environment.TickCount;
        int dxTol = Math.Max(4, GetSystemMetrics(SM_CXDOUBLECLK) / 2);
        int dyTol = Math.Max(4, GetSystemMetrics(SM_CYDOUBLECLK) / 2);
        uint dbl = GetDoubleClickTime();

        bool isDbl = lastDownValid
            && (uint)(now - lastDownTick) <= dbl
            && Math.Abs(pt.X - lastDown.X) <= dxTol
            && Math.Abs(pt.Y - lastDown.Y) <= dyTol;

        lastDown = pt;
        lastDownTick = now;
        lastDownValid = true;

        if (!isDbl || !AltDown()) return;

        // 消费掉这次双击判定，避免三连击误触第二次
        lastDownValid = false;

        if (cornerA == null) {
            cornerA = pt;
            Log("CORNER1 " + pt.X + "," + pt.Y);
            return;
        }

        Point a = cornerA.Value;
        Point b = pt;
        cornerA = null;
        Log("CORNER2 " + b.X + "," + b.Y);
        SnapRegion(a, b);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && (int)m.WParam == HOTKEY_ID) SnapFullscreen();
        base.WndProc(ref m);
    }

    void SnapFullscreen() {
        SnapRect(SystemInformation.VirtualScreen, "full");
    }

    void SnapRegion(Point a, Point b) {
        int x = Math.Min(a.X, b.X);
        int y = Math.Min(a.Y, b.Y);
        int w = Math.Abs(a.X - b.X);
        int h = Math.Abs(a.Y - b.Y);
        if (w < 2 || h < 2) {
            Log("SHOT-SKIP region too small " + w + "x" + h);
            return;
        }
        SnapRect(new Rectangle(x, y, w, h), "region");
    }

    void SnapRect(Rectangle r, string tag) {
        try {
            using (Bitmap bmp = new Bitmap(r.Width, r.Height))
            using (Graphics g = Graphics.FromImage(bmp)) {
                g.CopyFromScreen(r.X, r.Y, 0, 0, bmp.Size);
                string f = Path.Combine(outDir, "shot_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".png");
                bmp.Save(f, ImageFormat.Png);
                Log("SHOT " + tag + " " + r.Width + "x" + r.Height + " saved " + Path.GetFileName(f));
            }
        } catch (Exception ex) { Log("SHOT-ERROR " + ex.Message); }
    }

    protected override void OnFormClosing(FormClosingEventArgs e) {
        UnregisterHotKey(this.Handle, HOTKEY_ID);
        if (mouseHook != IntPtr.Zero) {
            UnhookWindowsHookEx(mouseHook);
            mouseHook = IntPtr.Zero;
        }
        base.OnFormClosing(e);
    }

    protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); }
}

class Program {
    static Mutex mtx;
    [STAThread]
    static void Main() {
        bool created;
        mtx = new Mutex(true, "SilentShotSingleton_CtrlAltS", out created);
        if (!created) return;
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");
        Application.Run(new HotkeyCatcher(dir));
        GC.KeepAlive(mtx);
    }
}
