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
public enum CompressLevel { Light, Balanced, Strong }

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
    /// Chỉ còn để đọc cài đặt của bản cũ (3 mức). Bản mới dùng ShakeLevel.
    public Sensitivity Sensitivity { get; set; } = Sensitivity.Normal;
    /// Độ nhạy lắc 1…10: 1 = nhạy nhất, 10 = phải lắc mạnh. 0 = chưa chọn (lấy từ Sensitivity cũ).
    public int ShakeLevel { get; set; }
    public bool HotKeyEnabled { get; set; } = true;
    public uint HotKeyMods { get; set; } = NativeMethods.MOD_ALT | NativeMethods.MOD_SHIFT;
    public uint HotKeyVk { get; set; } = NativeMethods.VK_SPACE;
    public string HotKeyDisplay { get; set; } = "Alt+Shift+Space";
    // Sửa ảnh (giống bản Mac)
    public CompressLevel CompressLevel { get; set; } = CompressLevel.Balanced;
    /// Dung lượng tối đa của nút "< … MB", tính bằng KB
    public int TargetSizeKB { get; set; } = 1000;
    /// Cạnh dài tối đa của nút "Thu nhỏ", tính bằng pixel
    public int ResizeEdge { get; set; } = 1920;

    public static readonly int[] TargetSizeChoices = [200, 500, 1000, 2000, 5000];
    public static readonly int[] ResizeEdgeChoices = [1080, 1280, 1920, 2560, 3840];

    /// 500 -> "500 KB", 1000 -> "1 MB"
    public static string SizeLabel(int kb) => kb >= 1000 ? $"{kb / 1000} MB" : $"{kb} KB";
    public static int Quality(CompressLevel l) => l switch { CompressLevel.Light => 80, CompressLevel.Strong => 45, _ => 65 };
    public static string LevelLabel(CompressLevel l) => l switch
    {
        CompressLevel.Light => L("Light (best quality)", "Nhẹ (giữ nét nhất)"),
        CompressLevel.Strong => L("Strong (smallest)", "Mạnh (nhẹ nhất)"),
        _ => L("Balanced", "Cân bằng"),
    };

    public static AppSettings Current { get; } = Load();
    public static event Action? Changed;

    private static string FilePath => Path.Combine(Tools.Dir, "settings.json");

    /// Mỗi nhịp lắc phải đi xa tối thiểu (pixel), và số lần đổi chiều cần có
    /// Cùng công thức với bản Mac
    public int Level => ShakeLevel is >= 1 and <= 10 ? ShakeLevel : Sensitivity switch { Sensitivity.Easy => 2, Sensitivity.Hard => 8, _ => 5 };
    public int MinSwing => 20 + (Level - 1) * 4;
    public int Reversals => Level <= 3 ? 3 : Level <= 7 ? 4 : 5;

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

    public static bool LaunchAtStartup
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue("SATF") != null;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) key.SetValue("SATF", $"\"{Environment.ProcessPath}\"");
            else key.DeleteValue("SATF", false);
        }
    }
}
