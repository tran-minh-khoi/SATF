using System;
using System.IO;
using System.Windows;

namespace SATF;

/// Ghi lỗi vào %LOCALAPPDATA%\SATF\logs\satf.log và báo người dùng bằng câu dễ hiểu.
public static class Crash
{
    public static string LogFile => Path.Combine(Tools.Dir, "logs", "satf.log");

    public static void Log(Exception? ex)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogFile)!);
            File.AppendAllText(LogFile, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] v{AppInfo.Version} · {Environment.OSVersion}\n{ex}\n\n");
        }
        catch { }
    }

    public static void Report(Exception? ex, bool fatal)
    {
        Log(ex);
        if (!fatal)
        {
            try { ToastWindow.Show(L("Something went wrong", "Có lỗi nhỏ xảy ra"), L("SATF is still running. Please try that again.", "SATF vẫn chạy bình thường. Thử lại thao tác vừa rồi nhé."), ToastWindow.Style.Failure, 6); }
            catch { }
            return;
        }
        System.Windows.MessageBox.Show(
            L($"SATF ran into a problem and needs to close.\n\nIf this keeps happening, send this file to {AppInfo.Email} and we'll help:\n{LogFile}", $"SATF gặp lỗi và cần đóng lại.\n\nNếu lỗi lặp lại, gửi file sau cho {AppInfo.Email} để được hỗ trợ:\n{LogFile}"),
            "SATF", MessageBoxButton.OK, MessageBoxImage.Error);
        Environment.Exit(1);
    }
}

/// Thông tin app & nhà phát triển (lấy từ file .csproj)
public static class AppInfo
{
    public const string Developer = "Tran Minh Khoi";
    public const string Email = "contact@tranminhkhoi.dev";
    public const string Website = "https://tranminhkhoi.dev";

    public static string Version =>
        System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0";
}
