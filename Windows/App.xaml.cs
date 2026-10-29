using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Interop;

namespace SATF;

public partial class App : System.Windows.Application
{
    private static Mutex? _singleInstanceMutex;
    private NotifyIcon? _notifyIcon;
    private ShakeDetector? _shakeDetector;
    private readonly HotKeyManager _hotKeyManager = new();
    private Window? _hotKeyWindow;
    private RadialMenuWindow? _radial;

    public static App Instance => (App)Current;
    public ShelfWindow ShelfWindow { get; private set; } = null!;

    /// true = phím tắt đang bị app khác dùng
    public event Action<bool>? HotKeyFailed;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += (s, ev) => { ev.Handled = true; Crash.Report(ev.Exception, fatal: false); };
        AppDomain.CurrentDomain.UnhandledException += (s, ev) => Crash.Report(ev.ExceptionObject as Exception, fatal: true);
        System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (s, ev) => { ev.SetObserved(); Crash.Log(ev.Exception); };

        try { Start(); }
        catch (Exception ex) { Crash.Report(ex, fatal: true); }
    }

    private void Start()
    {
        _singleInstanceMutex = new Mutex(true, "Global\\SATF_SingleInstance_App", out bool createdNew);
        if (!createdNew)
        {
            ToastWindow.Show(L("SATF is already running", "SATF đang chạy rồi"), L("Look for the SATF icon at the right end of the taskbar", "Icon SATF ở góc phải thanh Taskbar"), seconds: 3);
            var quit = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(3.5) };
            quit.Tick += (s, ev) => Shutdown();
            quit.Start();
            return;
        }

        ShelfWindow = new ShelfWindow();
        SetupNotifyIcon();

        _shakeDetector = new ShakeDetector();
        _shakeDetector.OnShake += OpenRadialMenuAt;
        _shakeDetector.Start();

        // Cửa sổ ẩn để nhận phím tắt toàn cục
        _hotKeyWindow = new Window { Width = 0, Height = 0, WindowStyle = WindowStyle.None, ShowInTaskbar = false, ShowActivated = false };
        _hotKeyWindow.SourceInitialized += (s, ev) =>
        {
            _hotKeyManager.Attach(new WindowInteropHelper(_hotKeyWindow).Handle);
            _hotKeyManager.OnHotKey += HandleHotKey;
            ReloadHotKey();
        };
        _hotKeyWindow.Show();
        _hotKeyWindow.Hide();
        AppSettings.Changed += ReloadHotKey;
        AppSettings.Changed += () => { if (_notifyIcon != null) _notifyIcon.ContextMenuStrip = MakeMenu(); };

        ToastWindow.Show(L("SATF is ready", "SATF đã sẵn sàng"), AppSettings.Current.HowToUse(), seconds: 5);
        AddOnsWindow.InstallPendingFromInstaller();
    }

    private void ReloadHotKey() => HotKeyFailed?.Invoke(!_hotKeyManager.Reload());

    /// Tạm tắt khi đang ghi phím tắt mới trong Cài đặt
    public void SuspendHotKey(bool suspended)
    {
        if (suspended) _hotKeyManager.Reload(suspended: true); else ReloadHotKey();
    }

    /// Đang giữ chuột (kéo file): mở menu tròn. Không thì mở/đóng khay.
    private void HandleHotKey()
    {
        bool dragging = (NativeMethods.GetAsyncKeyState(NativeMethods.VK_LBUTTON) & 0x8000) != 0;
        if (dragging && NativeMethods.GetCursorPos(out var pt)) OpenRadialMenuAt(pt.x, pt.y);
        else ShelfWindow.Toggle();
    }

    private void OpenRadialMenuAt(int x, int y)
    {
        _radial?.Close();
        _radial = new RadialMenuWindow();
        _radial.Closed += (s, e) => _radial = null;
        _radial.ShowAt(x, y);
    }

    private void SetupNotifyIcon()
    {
        Icon icon;
        try
        {
            // Icon nhúng sẵn trong SATF.exe
            icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? SystemIcons.Application;
        }
        catch { icon = SystemIcons.Application; }

        _notifyIcon = new NotifyIcon { Icon = icon, Visible = true, Text = "SATF", ContextMenuStrip = MakeMenu() };
        _notifyIcon.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) ShelfWindow.Toggle(); };
    }

    private ContextMenuStrip MakeMenu()
    {
        var menu = new ContextMenuStrip();
        // Bấm vào tên app ở đầu menu = mở cửa sổ ủng hộ
        menu.Items.Add(new ToolStripMenuItem("SATF  ♥", null, (s, e) => DonateWindow.ShowSingle())
        {
            Font = new Font(menu.Font, System.Drawing.FontStyle.Bold),
            ForeColor = System.Drawing.Color.FromArgb(UI.Donate.R, UI.Donate.G, UI.Donate.B),
            ToolTipText = L("Support SATF", "Ủng hộ SATF"),
        });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(L("Open Shelf", "Mở khay"), null, (s, e) => ShelfWindow.Toggle()));
        menu.Items.Add(new ToolStripMenuItem(L("Add-ons…", "Gói tải thêm…"), null, (s, e) => AddOnsWindow.Open()));
        menu.Items.Add(new ToolStripMenuItem(L("Settings…", "Cài đặt…"), null, (s, e) => SettingsWindow.ShowSingle()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(L("Report a Bug…", "Báo lỗi…"), null, (s, e) => SendFeedback(
            L("SATF bug report", "SATF - Báo lỗi"),
            L("What happened?\n\n\nWhat did you expect?\n\n\nSteps to reproduce:\n1. \n2. \n",
              "Chuyện gì đã xảy ra?\n\n\nBạn mong muốn điều gì?\n\n\nCác bước để gặp lỗi:\n1. \n2. \n"))));
        menu.Items.Add(new ToolStripMenuItem(L("Suggest a Feature…", "Góp ý tính năng…"), null, (s, e) => SendFeedback(
            L("SATF feature idea", "SATF - Góp ý tính năng"),
            L("I'd love SATF to…\n\n\nIt would help me because…\n", "Mình muốn SATF có thể…\n\n\nĐiều này giúp mình…\n"))));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem(L("Support SATF…", "Ủng hộ SATF…"), null, (s, e) => DonateWindow.ShowSingle()));
        if (!AppInfo.IsPackaged) // bản Store gỡ bằng Settings → Apps như mọi app Store khác
            menu.Items.Add(new ToolStripMenuItem(L("Uninstall SATF…", "Gỡ SATF khỏi máy…"), null, (s, e) => Uninstall()));
        menu.Items.Add(new ToolStripMenuItem(L("Quit SATF", "Thoát"), null, (s, e) => Shutdown()));

        return menu;
    }

    /// Mở app mail với thư soạn sẵn gửi nhà phát triển
    private static void SendFeedback(string subject, string body)
    {
        var full = body + $"\n—\nSATF {AppInfo.Version} · {Environment.OSVersion}";
        var mailto = $"mailto:{AppInfo.Email}?subject={Uri.EscapeDataString(subject)}&body={Uri.EscapeDataString(full)}";
        try { Process.Start(new ProcessStartInfo(mailto) { UseShellExecute = true }); }
        catch
        {
            // Máy chưa cài app mail: copy địa chỉ để người dùng tự gửi
            System.Windows.Clipboard.SetText(AppInfo.Email);
            ToastWindow.Show(L("No mail app found", "Chưa có app mail"), L($"Email address copied: {AppInfo.Email}", $"Đã copy địa chỉ: {AppInfo.Email}"));
        }
    }

    // MARK: - Gỡ cài đặt

    /// Xoá sạch mọi thứ SATF tạo ra trên máy, kể cả chính file SATF.exe.
    private void Uninstall()
    {
        // Cài bằng bộ cài: dùng bộ gỡ chuẩn (cũng là cái chạy khi gỡ từ Control Panel)
        var uninstaller = Path.Combine(AppContext.BaseDirectory, "Uninstall.exe");
        if (File.Exists(uninstaller))
        {
            Process.Start(new ProcessStartInfo(uninstaller) { UseShellExecute = true });
            return;
        }

        var answer = System.Windows.MessageBox.Show(
            L("SATF and everything that came with it (settings, add-ons) will be removed from this PC.", "SATF và mọi thứ đi kèm (cài đặt, gói tải thêm) sẽ được xoá khỏi máy."),
            L("Uninstall SATF?", "Gỡ SATF khỏi máy?"), MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel);
        if (answer != MessageBoxResult.OK) return;

        try { AppSettings.LaunchAtStartup = false; } catch { }
        var temp = Path.GetTempPath();
        foreach (var dir in new[] { Tools.Dir, Path.Combine(temp, "satf-lo-profile") })
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch { }
        }

        // SATF.exe và phần chạy kèm đang được dùng, nên xoá sau khi app đã thoát
        var exe = Environment.ProcessPath ?? "";
        var extracted = Path.Combine(temp, ".net", "SATF");
        Process.Start(new ProcessStartInfo("cmd.exe",
            $"/c timeout /t 2 /nobreak >nul & del /f /q \"{exe}\" & rmdir /s /q \"{extracted}\" & rmdir /s /q \"{Tools.Dir}\"")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            WorkingDirectory = temp,
        });
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _shakeDetector?.Dispose();
        _hotKeyManager.Dispose();
        if (_notifyIcon != null) { _notifyIcon.Visible = false; _notifyIcon.Dispose(); }
        try { _singleInstanceMutex?.ReleaseMutex(); } catch { }
        _singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }
}
