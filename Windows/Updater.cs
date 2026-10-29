using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Threading;

namespace SATF;

/// Tự cập nhật: hỏi GitHub bản mới nhất, có bản mới thì báo. Bấm vào là tải bộ cài,
/// kiểm tra SHA-256 khớp với GitHub, chạy cài đặt im lặng rồi mở lại SATF.
/// Không cần máy chủ riêng (giống bản Mac).
public static class Updater
{
    public record Release(string Version, string PageUrl, string SetupUrl, string? Sha256);

    private const string LatestApi = "https://api.github.com/repos/tran-minh-khoi/SATF/releases/latest";
    private const string DownloadPrefix = "https://github.com/tran-minh-khoi/SATF/releases/download/";

    private static readonly HttpClient Http = CreateClient();
    private static DispatcherTimer? _timer;

    /// Bản mới hơn bản đang chạy (null = đang là bản mới nhất / chưa kiểm tra)
    public static Release? Available { get; private set; }
    public static bool Installing { get; private set; }
    /// Có / hết bản mới: dựng lại menu
    public static event Action? Changed;

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"SATF/{AppInfo.Version} (Windows)");
        return client;
    }

    /// Kiểm tra lúc mở app (sau một lát) và mỗi ngày một lần khi app chạy liên tục
    public static void Start()
    {
        var first = new DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
        first.Tick += (s, e) => { first.Stop(); AutoCheck(); };
        first.Start();
        _timer = new DispatcherTimer { Interval = TimeSpan.FromHours(24) };
        _timer.Tick += (s, e) => AutoCheck();
        _timer.Start();
    }

    private static void AutoCheck()
    {
        if (AppSettings.Current.AutoUpdateCheck) _ = Check(userInitiated: false);
    }

    // MARK: - Kiểm tra

    public static async Task Check(bool userInitiated)
    {
        Release? release = null;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, LatestApi);
            request.Headers.Accept.ParseAdd("application/vnd.github+json");
            using var response = await Http.SendAsync(request);
            if (response.IsSuccessStatusCode) release = Parse(await response.Content.ReadAsStringAsync());
        }
        catch { }

        if (release == null)
        {
            if (userInitiated)
                ToastWindow.Show(L("Couldn't check for updates", "Không kiểm tra được bản mới"),
                    L("Check your internet connection and try again.", "Kiểm tra kết nối mạng rồi thử lại nhé."), ToastWindow.Style.Failure);
            return;
        }

        if (IsNewer(release.Version, AppInfo.Version))
        {
            var changed = Available?.Version != release.Version;
            Available = release;
            if (changed) Changed?.Invoke();
            ToastWindow.Show(L($"SATF {release.Version} is available", $"Đã có SATF {release.Version}"),
                L("Click to update now", "Bấm để cập nhật ngay"), seconds: 15, onClick: () => _ = Install());
        }
        else
        {
            if (Available != null) { Available = null; Changed?.Invoke(); }
            if (userInitiated)
                ToastWindow.Show(L("SATF is up to date", "SATF đang là bản mới nhất"),
                    L($"Version {AppInfo.Version}", $"Phiên bản {AppInfo.Version}"), ToastWindow.Style.Success);
        }
    }

    public static Release? Parse(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.TryGetProperty("draft", out var draft) && draft.ValueKind == JsonValueKind.True) return null;
            if (root.TryGetProperty("prerelease", out var pre) && pre.ValueKind == JsonValueKind.True) return null;

            var tag = root.GetProperty("tag_name").GetString() ?? "";
            var page = root.GetProperty("html_url").GetString() ?? "";
            var setup = root.GetProperty("assets").EnumerateArray().FirstOrDefault(a =>
            {
                var name = a.GetProperty("name").GetString() ?? "";
                return name.StartsWith("SATF-Setup", StringComparison.OrdinalIgnoreCase) && name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);
            });
            if (setup.ValueKind != JsonValueKind.Object) return null;

            var url = setup.GetProperty("browser_download_url").GetString() ?? "";
            if (!url.StartsWith(DownloadPrefix, StringComparison.Ordinal)) return null;

            string? sha = null;
            if (setup.TryGetProperty("digest", out var digest) && digest.GetString() is { } d && d.StartsWith("sha256:"))
                sha = d["sha256:".Length..].ToLowerInvariant();

            var version = tag.StartsWith('v') ? tag[1..] : tag;
            return new Release(version, page, url, sha);
        }
        catch { return null; }
    }

    /// "1.2.1" > "1.2.0"
    public static bool IsNewer(string a, string b)
    {
        int[] Parts(string v) => v.Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).ToArray();
        var x = Parts(a);
        var y = Parts(b);
        for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
        {
            var p = i < x.Length ? x[i] : 0;
            var q = i < y.Length ? y[i] : 0;
            if (p != q) return p > q;
        }
        return false;
    }

    // MARK: - Cài bản mới

    public static async Task Install()
    {
        var release = Available;
        if (release == null || Installing) return;
        // Bộ cài Windows chưa có chữ ký số: SHA-256 từ GitHub là lớp kiểm tra duy nhất.
        // Không có thì không tự chạy, mở trang tải để người dùng tự cài.
        if (release.Sha256 == null)
        {
            Process.Start(new ProcessStartInfo(release.PageUrl) { UseShellExecute = true });
            return;
        }
        Installing = true;
        ToastWindow.Show(L($"Downloading SATF {release.Version}…", $"Đang tải SATF {release.Version}…"),
            L("SATF will restart when it's done", "Xong SATF sẽ tự mở lại"), ToastWindow.Style.Working, seconds: null);

        var setup = Path.Combine(Path.GetTempPath(), $"SATF-Setup-{release.Version}-{Guid.NewGuid():N}.exe");
        try
        {
            // 1. Tải bộ cài
            using (var response = await Http.GetAsync(release.SetupUrl, HttpCompletionOption.ResponseHeadersRead))
            {
                response.EnsureSuccessStatusCode();
                await using var file = File.Create(setup);
                await response.Content.CopyToAsync(file);
            }

            // 2. File tải về đúng là file trên GitHub
            await using (var file = File.OpenRead(setup))
            {
                var hash = Convert.ToHexString(await SHA256.HashDataAsync(file)).ToLowerInvariant();
                if (hash != release.Sha256) throw new UpdateException(L("The download is damaged.", "File tải về bị hỏng."));
            }

            // 3. Đã cài bằng bộ cài: cài im lặng rồi mở lại. Bản chạy luôn (không cài): mở bộ cài như bình thường.
            var installed = File.Exists(Path.Combine(AppContext.BaseDirectory, "Uninstall.exe"));
            Process.Start(new ProcessStartInfo(setup)
            {
                Arguments = installed ? "/S /RELAUNCH" : "",
                UseShellExecute = true,
            });
            ToastWindow.Show(L($"Installing SATF {release.Version}…", $"Đang cài SATF {release.Version}…"),
                L("SATF will restart in a moment", "SATF sẽ mở lại sau giây lát"), ToastWindow.Style.Success, seconds: 3);
            // Bộ cài sẽ đóng SATF; thoát trước cho gọn
            var quit = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
            quit.Tick += (s, e) => { quit.Stop(); App.Instance.Shutdown(); };
            quit.Start();
        }
        catch (Exception ex)
        {
            Installing = false;
            try { File.Delete(setup); } catch { }
            var reason = ex is UpdateException u ? u.Message + " " : "";
            ToastWindow.Show(L("Couldn't update SATF", "Chưa cập nhật được SATF"),
                reason + L("Click to download it from GitHub.", "Bấm để tải từ GitHub."), ToastWindow.Style.Failure, seconds: 12,
                onClick: () => Process.Start(new ProcessStartInfo(release.PageUrl) { UseShellExecute = true }));
        }
    }

    private class UpdateException(string message) : Exception(message);
}
