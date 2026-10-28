using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

using Brushes = System.Windows.Media.Brushes;
using CheckBox = System.Windows.Controls.CheckBox;
using ProgressBar = System.Windows.Controls.ProgressBar;

namespace SATF;

public enum AddOn { Office, Media }

/// Công cụ phụ tải thêm, nằm trong %LOCALAPPDATA%\SATF (không cần quyền admin).
public static class Tools
{
    public static readonly string Dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SATF");
    private static readonly string LibreOfficeDir = Path.Combine(Dir, "LibreOffice");
    private static readonly string FFmpegExe = Path.Combine(Dir, "ffmpeg.exe");

    public static string? Soffice =>
        (Directory.Exists(LibreOfficeDir)
            ? Directory.EnumerateFiles(LibreOfficeDir, "soffice.exe", SearchOption.AllDirectories).FirstOrDefault()
            : null)
        ?? new[] { Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86 }
            .Select(f => Path.Combine(Environment.GetFolderPath(f), "LibreOffice", "program", "soffice.exe"))
            .FirstOrDefault(File.Exists);

    /// null = không có (kể cả trong PATH)
    public static string? FFmpeg
    {
        get
        {
            if (File.Exists(FFmpegExe)) return FFmpegExe;
            var path = Environment.GetEnvironmentVariable("PATH") ?? "";
            return path.Split(Path.PathSeparator).Select(d => Path.Combine(d.Trim(), "ffmpeg.exe")).FirstOrDefault(File.Exists);
        }
    }

    public static bool HasMicrosoftOffice =>
        Type.GetTypeFromProgID("Excel.Application") != null || Type.GetTypeFromProgID("PowerPoint.Application") != null;

    /// Đã tải về bởi SATF (xoá được)
    public static bool Downloaded(AddOn a) => a == AddOn.Office ? Directory.Exists(LibreOfficeDir) : File.Exists(FFmpegExe);

    /// Dùng được (tải về, hoặc máy có sẵn)
    public static bool Available(AddOn a) => a == AddOn.Office ? Soffice != null : FFmpeg != null;

    public static long DiskSize(AddOn a)
    {
        try
        {
            if (a == AddOn.Media) return File.Exists(FFmpegExe) ? new FileInfo(FFmpegExe).Length : 0;
            return Directory.Exists(LibreOfficeDir)
                ? Directory.EnumerateFiles(LibreOfficeDir, "*", SearchOption.AllDirectories).Sum(f => new FileInfo(f).Length)
                : 0;
        }
        catch { return 0; }
    }

    public static void Remove(AddOn a)
    {
        if (a == AddOn.Office) { if (Directory.Exists(LibreOfficeDir)) Directory.Delete(LibreOfficeDir, true); }
        else if (File.Exists(FFmpegExe)) File.Delete(FFmpegExe);
    }

    public static Task Install(AddOn a, Action<double, string> report) =>
        a == AddOn.Office ? InstallLibreOffice(report) : InstallFFmpeg(report);

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromHours(1) };

    public static async Task InstallLibreOffice(Action<double, string> report)
    {
        const string baseUrl = "https://download.documentfoundation.org/libreoffice/stable/";
        report(0, L("Getting ready…", "Đang chuẩn bị…"));
        var html = await Http.GetStringAsync(baseUrl);
        var version = Regex.Matches(html, @"href=""(\d+(?:\.\d+)+)/""")
            .Select(m => m.Groups[1].Value)
            .MaxBy(v => Version.Parse(v))
            ?? throw new InvalidOperationException(L("Couldn't download right now. Please try again later.", "Chưa tải được, thử lại sau nhé"));

        var msi = Path.Combine(Path.GetTempPath(), $"satf-libreoffice-{version}.msi");
        await Download($"{baseUrl}{version}/win/x86_64/LibreOffice_{version}_Win_x86-64.msi", msi,
                       L("Downloading the Office add-on", "Đang tải gói Office"), report);
        try
        {
            report(1, L("Installing… (about 1–2 minutes)", "Đang cài… (khoảng 1–2 phút)"));
            if (Directory.Exists(LibreOfficeDir)) Directory.Delete(LibreOfficeDir, true);
            // Giải nén MSI vào thư mục riêng, không cần quyền admin, không đụng vào hệ thống
            await RunAsync("msiexec", $"/a \"{msi}\" /qn TARGETDIR=\"{LibreOfficeDir}\"");
        }
        finally { File.Delete(msi); }

        if (Soffice == null) throw new InvalidOperationException(L("Install didn't finish. Please try again.", "Cài không thành công, thử lại nhé"));
    }

    public static async Task InstallFFmpeg(Action<double, string> report)
    {
        var zip = Path.Combine(Path.GetTempPath(), "satf-ffmpeg.zip");
        await Download("https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip", zip, L("Downloading the video & music add-on", "Đang tải gói video & nhạc"), report);
        try
        {
            report(1, L("Installing…", "Đang cài…"));
            Directory.CreateDirectory(Dir);
            using var archive = ZipFile.OpenRead(zip);
            var entry = archive.Entries.FirstOrDefault(e => e.FullName.EndsWith("/bin/ffmpeg.exe", StringComparison.OrdinalIgnoreCase))
                ?? throw new InvalidOperationException(L("Install didn't finish. Please try again.", "Cài không thành công, thử lại nhé"));
            entry.ExtractToFile(FFmpegExe, overwrite: true);
        }
        finally { File.Delete(zip); }
    }

    private static async Task Download(string url, string dst, string label, Action<double, string> report)
    {
        using var resp = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        resp.EnsureSuccessStatusCode();
        long total = resp.Content.Headers.ContentLength ?? 0, done = 0;
        await using var input = await resp.Content.ReadAsStreamAsync();
        await using var output = File.Create(dst);
        var buffer = new byte[1 << 16];
        int n;
        var lastReport = DateTime.MinValue;
        while ((n = await input.ReadAsync(buffer)) > 0)
        {
            await output.WriteAsync(buffer.AsMemory(0, n));
            done += n;
            if ((DateTime.Now - lastReport).TotalMilliseconds > 150)
            {
                lastReport = DateTime.Now;
                report(total > 0 ? (double)done / total : 0, $"{label}… {done >> 20} / {total >> 20} MB");
            }
        }
    }

    private static Task RunAsync(string exe, string args) => Task.Run(() =>
    {
        using var p = Process.Start(new ProcessStartInfo(exe, args) { CreateNoWindow = true, UseShellExecute = false })!;
        p.WaitForExit();
    });
}

/// Quản lý gói tải thêm: tải / xoá từng gói. Mở ở 3 chỗ: sau khi cài (gói đã tick trong bộ cài),
/// khi thiếu gói lúc chuyển file, và từ menu / Cài đặt.
public class AddOnsWindow : Window
{
    public enum Reason { Manage, Needed, Installer }

    private static AddOnsWindow? _open;
    private static readonly string PendingFile = Path.Combine(Tools.Dir, "pending-addons");

    private readonly Reason _reason;
    private readonly Action? _onReady;
    private readonly AddOn? _needed;
    private readonly StackPanel _rows = new();
    private readonly ProgressBar _progress = new() { Height = 6, Maximum = 1, Visibility = Visibility.Collapsed, Margin = new Thickness(0, 4, 0, 4) };
    private readonly TextBlock _status = new() { FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap };
    private readonly Button _close = new() { Width = 90, Padding = new Thickness(0, 4, 0, 4), IsCancel = true };
    private AddOn? _busy;

    /// `onReady`: chạy tiếp việc đang dở sau khi tải xong (ví dụ chuyển file vừa thả)
    public static void Open(Reason reason = Reason.Manage, AddOn? needed = null, Action? onReady = null, AddOn[]? autoStart = null)
    {
        if (_open is { _busy: not null }) { _open.Activate(); return; }
        _open?.Close();
        _open = new AddOnsWindow(reason, needed, onReady);
        _open.Closed += (s, e) => _open = null;
        _open.Show();
        _open.Activate();
        if (autoStart?.Length > 0) _ = _open.InstallMany(autoStart);
    }

    /// Gói người dùng đã tick trong bộ cài -> tải ngay ở lần mở đầu tiên
    public static void InstallPendingFromInstaller()
    {
        if (!File.Exists(PendingFile)) return;
        var wanted = File.ReadAllText(PendingFile);
        try { File.Delete(PendingFile); } catch { }
        var list = new System.Collections.Generic.List<AddOn>();
        if (wanted.Contains("office") && !Tools.Available(AddOn.Office)) list.Add(AddOn.Office);
        if (wanted.Contains("media") && !Tools.Available(AddOn.Media)) list.Add(AddOn.Media);
        if (list.Count > 0) Open(Reason.Installer, autoStart: list.ToArray());
    }

    private AddOnsWindow(Reason reason, AddOn? needed, Action? onReady)
    {
        _reason = reason;
        _needed = needed;
        _onReady = onReady;
        Title = L("Add-ons", "Gói tải thêm");
        Icon = UI.AppIcon;
        Width = 500;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true;

        var root = new StackPanel { Margin = new Thickness(20) };
        var (title, text) = reason switch
        {
            Reason.Needed => (L("One more step", "Cần thêm một bước"),
                              L("To convert this file, SATF needs the add-on below. Your file will be converted as soon as it's ready.",
                                "Để đổi file này, SATF cần gói bên dưới. Tải xong file sẽ được đổi ngay.")),
            Reason.Installer => (L("Finishing setup", "Đang hoàn tất cài đặt"),
                                 L("Downloading the add-ons you picked. You can keep using SATF meanwhile.",
                                   "Đang tải các gói bạn đã chọn. Bạn vẫn dùng SATF bình thường trong lúc chờ.")),
            _ => (L("Add-ons", "Gói tải thêm"),
                  L("Images and PDF work right away. Add more only when you need it.",
                    "Ảnh và PDF đã dùng được ngay. Chỉ thêm khi bạn cần.")),
        };
        root.Children.Add(new TextBlock { Text = title, FontSize = 16, FontWeight = FontWeights.SemiBold });
        root.Children.Add(new TextBlock { Text = text, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 14) });
        root.Children.Add(_rows);
        root.Children.Add(_progress);
        root.Children.Add(_status);

        var bottom = new DockPanel { Margin = new Thickness(0, 14, 0, 0), LastChildFill = false };
        var hint = new TextBlock
        {
            Text = L("Remove add-ons anytime to free up space.", "Xoá gói bất cứ lúc nào để giải phóng dung lượng."),
            FontSize = 11, Foreground = Brushes.Gray, VerticalAlignment = VerticalAlignment.Center,
        };
        DockPanel.SetDock(hint, Dock.Left);
        DockPanel.SetDock(_close, Dock.Right);
        bottom.Children.Add(hint);
        bottom.Children.Add(_close);
        root.Children.Add(bottom);
        Content = root;

        _close.Content = reason == Reason.Needed ? L("Not now", "Để sau") : L("Done", "Xong");
        _close.Click += (s, e) => Close();
        Closing += (s, e) => e.Cancel = _busy != null;
        Refresh();
    }

    private void Refresh()
    {
        _rows.Children.Clear();
        foreach (var a in new[] { AddOn.Office, AddOn.Media })
        {
            if (_reason == Reason.Needed && _needed != a) continue;   // chỉ hiện gói đang cần
            _rows.Children.Add(Row(a));
        }
        _close.IsEnabled = _busy == null;
    }

    private FrameworkElement Row(AddOn a)
    {
        bool office = a == AddOn.Office;
        string title = office ? L("Word, Excel & PowerPoint", "Word, Excel & PowerPoint") : L("Video & music", "Video & nhạc");
        string what = office ? L("Convert documents to PDF and images", "Đổi tài liệu sang PDF và ảnh")
                             : L("MP4, MP3, M4A, WAV · pull the audio out of videos", "MP4, MP3, M4A, WAV · lấy tiếng từ video");
        string state;
        if (Tools.Downloaded(a)) state = L("Installed", "Đã cài") + $" · {Tools.DiskSize(a) / 1_048_576} MB";
        else if (Tools.Available(a)) state = L("Already available on this PC", "Máy đã có sẵn");
        else if (office && Tools.HasMicrosoftOffice) state = L("Optional — Microsoft Office already handles this", "Không bắt buộc — Microsoft Office đã làm được");
        else state = office ? L("Not installed · about 350 MB download", "Chưa cài · tải khoảng 350 MB")
                            : L("Not installed · about 115 MB download", "Chưa cài · tải khoảng 115 MB");

        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold });
        text.Children.Add(new TextBlock { Text = what, FontSize = 12 });
        text.Children.Add(new TextBlock { Text = state, FontSize = 11, Foreground = Brushes.Gray });

        FrameworkElement action;
        if (_busy == a) action = UI.Spinner(20, UI.Convert);
        else if (Tools.Downloaded(a))
        {
            var remove = new Button { Content = L("Remove", "Xoá"), Width = 90, Padding = new Thickness(0, 4, 0, 4), IsEnabled = _busy == null };
            remove.Click += async (s, e) =>
            {
                _busy = a;
                _status.Text = L("Removing…", "Đang xoá…");
                Refresh();
                try { await Task.Run(() => Tools.Remove(a)); _status.Text = ""; }
                catch { _status.Text = L("Couldn't remove it. Close SATF conversions and try again.", "Chưa xoá được. Đợi chuyển file xong rồi thử lại nhé."); }
                _busy = null;
                Refresh();
            };
            action = remove;
        }
        else if (!Tools.Available(a))
        {
            var download = new Button { Content = L("Download", "Tải về"), Width = 90, Padding = new Thickness(0, 4, 0, 4), IsDefault = true, IsEnabled = _busy == null };
            download.Click += async (s, e) => await InstallMany(new[] { a });
            action = download;
        }
        else action = new TextBlock();

        var dock = new DockPanel();
        var icon = UI.Glyph(office ? "\uE8A5" : "\uE714", 22, new SolidColorBrush(UI.Convert));
        icon.Width = 36;
        icon.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(icon, Dock.Left);
        action.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(action, Dock.Right);
        dock.Children.Add(icon);
        dock.Children.Add(action);
        dock.Children.Add(text);
        return new Border
        {
            Child = dock,
            Padding = new Thickness(12),
            Margin = new Thickness(0, 0, 0, 8),
            CornerRadius = new CornerRadius(8),
            Background = new SolidColorBrush(Color.FromArgb(0x0D, 0, 0, 0)),
        };
    }

    private async Task InstallMany(AddOn[] list)
    {
        _progress.Visibility = Visibility.Visible;
        _status.Foreground = Brushes.Gray;
        void Report(double p, string text) => Dispatcher.Invoke(() => { _progress.Value = p; _status.Text = text; });
        try
        {
            foreach (var a in list)
            {
                if (Tools.Available(a)) continue;
                _busy = a;
                Refresh();
                await Tools.Install(a, Report);
            }
            _busy = null;
            _progress.Visibility = Visibility.Collapsed;
            if (_onReady != null) { Close(); _onReady(); return; }
            _status.Text = L("All set! Ready to use.", "Xong! Giờ đã dùng được rồi.");
            _status.Foreground = Brushes.Green;
        }
        catch (Exception ex)
        {
            Crash.Log(ex);
            _status.Text = ex is HttpRequestException or TaskCanceledException
                ? L("Download didn't finish. Check your internet and try again.", "Tải không thành công. Kiểm tra mạng rồi thử lại nhé.")
                : ex.Message;
            _status.Foreground = Brushes.Red;
        }
        finally
        {
            _busy = null;
            _progress.Visibility = Visibility.Collapsed;
            if (IsLoaded) Refresh();
        }
    }
}
