// SilentShot —— 真·无窗口后台热键截图程序（GUI 子系统，编译为 winexe）。
// 与 PowerShell 宿主方案的本质区别：GUI 子系统进程根本不分配控制台窗口，
// 屏幕上没有任何窗口可被误关。要停止它，只能在任务管理器里结束 SilentShot.exe。
//
// 热键 Ctrl+Alt+S：静默截全屏（含多显示器），存到 我的图片\Screenshots\shot_*.png。
// 无遮罩 / 无通知 / 无声音 —— 投屏 / 会议中不被发现。
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

    const int WM_HOTKEY = 0x0312;
    const int HOTKEY_ID = 0xB001;
    const uint MOD_CTRL_ALT = 0x0002 | 0x0001;   // MOD_ALT=1 | MOD_CONTROL=2
    const uint VK_S = 0x53;                        // 'S'

    string outDir;
    string logFile;

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
        Log(ok ? "STARTED hotkey Ctrl+Alt+S registered (exe)" : "ERROR hotkey register failed");
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && (int)m.WParam == HOTKEY_ID) Snap();
        base.WndProc(ref m);
    }

    void Snap() {
        try {
            Rectangle b = SystemInformation.VirtualScreen;
            using (Bitmap bmp = new Bitmap(b.Width, b.Height))
            using (Graphics g = Graphics.FromImage(bmp)) {
                g.CopyFromScreen(b.X, b.Y, 0, 0, bmp.Size);
                string f = Path.Combine(outDir, "shot_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".png");
                bmp.Save(f, ImageFormat.Png);
                Log("SHOT saved " + Path.GetFileName(f));
            }
        } catch (Exception ex) { Log("SHOT-ERROR " + ex.Message); }
    }

    protected override void OnFormClosing(FormClosingEventArgs e) {
        UnregisterHotKey(this.Handle, HOTKEY_ID);
        base.OnFormClosing(e);
    }

    protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); }
}

class Program {
    static Mutex mtx;
    [STAThread]
    static void Main() {
        // 单实例守卫：重复启动直接退出，避免多个实例抢同一热键
        bool created;
        mtx = new Mutex(true, "SilentShotSingleton_CtrlAltS", out created);
        if (!created) return;
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");
        Application.Run(new HotkeyCatcher(dir));
        GC.KeepAlive(mtx);
    }
}
