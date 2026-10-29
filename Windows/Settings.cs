using System;
using System.IO;
using System.Text.Json;
using Microsoft.Win32;

namespace SATF;

public enum Language { En, Vi }

public static class Lang
{
    /// Câu chữ theo ngôn ngữ đang chọn: L("English", "Tiếng Việt"). Mặc định tiếng Anh.
    public static string L(string en, string vi) => AppSettings.Current.Language == Language.Vi ? vi : en;
}

public enum ShakeModifier { None, Shift, Ctrl, Alt }
public enum Sensitivity { Easy, Normal, Hard }

/// Cài đặt, lưu ở %LOCALAPPDATA%\SATF\settings.json (giống bản Mac).
public class AppSettings
{
    public Language Language { get; set; } = Language.En;
    /// App giải nén: "" = hỏi khi máy có app khác, "builtin" = SATF, còn lại là id trong Archivers
    public string Extractor { get; set; } = "";
    /// App nén ZIP: "builtin" = SATF, còn lại là id trong Archivers
    public string Compressor { get; set; } = Archivers.Builtin;
    public bool ShakeEnabled { get; set; } = true;
    public ShakeModifier ShakeModifier { get; set; } = ShakeModifier.Shift;
    public Sensitivity Sensitivity { get; set; } = Sensitivity.Normal;
    public bool HotKeyEnabled { get; set; } = true;
    public uint HotKeyMods { get; set; } = NativeMethods.MOD_ALT | NativeMethods.MOD_SHIFT;
    public uint HotKeyVk { get; set; } = NativeMethods.VK_SPACE;
    public string HotKeyDisplay { get; set; } = "Alt+Shift+Space";

    public static AppSettings Current { get; } = Load();
    public static event Action? Changed;

    private static string FilePath => Path.Combine(Tools.Dir, "settings.json");

    /// Mỗi nhịp lắc phải đi xa tối thiểu (pixel), và số lần đổi chiều cần có
    public int MinSwing => Sensitivity switch { Sensitivity.Easy => 25, Sensitivity.Hard => 50, _ => 35 };
    public int Reversals => Sensitivity switch { Sensitivity.Easy => 3, Sensitivity.Hard => 5, _ => 4 };

    public string ModifierLabel => ShakeModifier switch
    {
        ShakeModifier.Shift => "Shift", ShakeModifier.Ctrl => "Ctrl", ShakeModifier.Alt => "Alt", _ => "",
    };

    private static AppSettings Load()
    {
        try { return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new(); }
        catch { return new(); }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Tools.Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this));
        }
        catch { }
        Changed?.Invoke();
    }

    /// Ví dụ: "Kéo file, giữ Shift rồi lắc nhẹ, hoặc bấm Alt+Shift+Space"
    public string HowToUse()
    {
        var ways = new System.Collections.Generic.List<string>();
        if (ShakeEnabled) ways.Add(ShakeModifier == ShakeModifier.None ? L("Drag a file and give it a little shake", "Kéo file rồi lắc nhẹ") : L($"Drag a file, hold {ModifierLabel} and give it a shake", $"Kéo file, giữ {ModifierLabel} rồi lắc nhẹ"));
        if (HotKeyEnabled) ways.Add(ways.Count == 0 ? L($"Drag a file and press {HotKeyDisplay}", $"Kéo file rồi bấm {HotKeyDisplay}") : L($"press {HotKeyDisplay}", $"bấm {HotKeyDisplay}"));
        return ways.Count == 0 ? L("Click the SATF icon at the right end of the taskbar to get started", "Bấm icon SATF ở góc phải thanh Taskbar để bắt đầu") : string.Join(L(", or ", ", hoặc "), ways);
    }

    // MARK: - Mở cùng Windows

    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    // Bản Store: Run key bị ảo hoá trong gói MSIX nên không có tác dụng, phải dùng StartupTask (khai báo trong AppxManifest.xml)
    private const string StartupTaskId = "SATFStartup";

    public static bool LaunchAtStartup
    {
        get
        {
            if (AppInfo.IsPackaged)
            {
                var task = Windows.ApplicationModel.StartupTask.GetAsync(StartupTaskId).AsTask().GetAwaiter().GetResult();
                return task.State is Windows.ApplicationModel.StartupTaskState.Enabled or Windows.ApplicationModel.StartupTaskState.EnabledByPolicy;
            }
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue("SATF") != null;
        }
        set
        {
            if (AppInfo.IsPackaged)
            {
                // Người dùng đã tắt trong Task Manager → Windows không cho app tự bật lại
                var task = Windows.ApplicationModel.StartupTask.GetAsync(StartupTaskId).AsTask().GetAwaiter().GetResult();
                if (value) task.RequestEnableAsync().AsTask().GetAwaiter().GetResult();
                else task.Disable();
                return;
            }
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) key.SetValue("SATF", $"\"{Environment.ProcessPath}\"");
            else key.DeleteValue("SATF", false);
        }
    }
}
