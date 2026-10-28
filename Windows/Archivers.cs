using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Brushes = System.Windows.Media.Brushes;
using Image = System.Windows.Controls.Image;
using RadioButton = System.Windows.Controls.RadioButton;
using Orientation = System.Windows.Controls.Orientation;

namespace SATF;

/// App giải nén / nén người dùng cài thêm, gọi qua dòng lệnh để file ra đúng chỗ.
public record ArchiveTool(string Id, string Name, string Exe);

public static class Archivers
{
    /// Giá trị lưu trong Cài đặt: "" = hỏi mỗi lần (chỉ với giải nén), "builtin" = SATF tự làm, còn lại là Id
    public const string Builtin = "builtin";

    private static readonly (string Id, string Name, string RelPath)[] Known =
    {
        ("7zip", "7-Zip", @"7-Zip\7z.exe"),
        ("winrar", "WinRAR", @"WinRAR\WinRAR.exe"),
        ("bandizip", "Bandizip", @"Bandizip\bz.exe"),
    };

    public static List<ArchiveTool> Installed
    {
        get
        {
            var roots = new[] { Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86 }
                .Select(Environment.GetFolderPath).Where(r => r.Length > 0).Distinct();
            return Known.Select(k => roots.Select(r => Path.Combine(r, k.RelPath)).FirstOrDefault(File.Exists) is string exe
                    ? new ArchiveTool(k.Id, k.Name, exe) : null)
                .OfType<ArchiveTool>().ToList();
        }
    }

    public static ArchiveTool? Find(string id) => Installed.FirstOrDefault(t => t.Id == id);

    public static string ExtractArgs(ArchiveTool t, string src, string dst) => t.Id switch
    {
        "7zip" => $"x \"{src}\" -o\"{dst}\" -y",
        "winrar" => $"x -ibck -y \"{src}\" \"{dst}\\\"",
        _ => $"x -o:\"{dst}\" -y \"{src}\"",   // Bandizip
    };

    public static string CompressArgs(ArchiveTool t, string src, string dst) => t.Id switch
    {
        "7zip" => $"a -tzip \"{dst}\" \"{src}\"",
        "winrar" => $"a -afzip -ibck -ep1 \"{dst}\" \"{src}\"",
        _ => $"c \"{dst}\" \"{src}\"",   // Bandizip
    };
}

/// Lần đầu giải nén mà máy có app khác: hỏi dùng app nào, chỉ lần này hay luôn dùng.
public class ArchiverChooser : Window
{
    private string _selected = Archivers.Builtin;

    public static void Open(List<ArchiveTool> tools, Action<string> done) => new ArchiverChooser(tools, done).Show();

    private ArchiverChooser(List<ArchiveTool> tools, Action<string> done)
    {
        Title = L("Extract with", "Giải nén bằng");
        Icon = UI.AppIcon;
        Width = 380;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true;

        var root = new StackPanel { Margin = new Thickness(20) };
        root.Children.Add(new TextBlock { Text = L("Which app should extract this file?", "Dùng app nào để giải nén file này?"),
                                          FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 10) });

        void Option(string id, string name, ImageSource? icon)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            if (icon != null) row.Children.Add(new Image { Source = icon, Width = 20, Height = 20, Margin = new Thickness(0, 0, 8, 0) });
            row.Children.Add(new TextBlock { Text = name, VerticalAlignment = VerticalAlignment.Center });
            var radio = new RadioButton { Content = row, GroupName = "tool", IsChecked = id == _selected, Margin = new Thickness(0, 4, 0, 4) };
            radio.Checked += (s, e) => _selected = id;
            root.Children.Add(radio);
        }
        Option(Archivers.Builtin, L("SATF (built-in)", "SATF (có sẵn)"), UI.AppIcon);
        foreach (var t in tools) Option(t.Id, t.Name, UI.FileIcon(t.Exe));

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
        var once = new Button { Content = L("Just once", "Chỉ lần này"), MinWidth = 90, Padding = new Thickness(8, 4, 8, 4), Margin = new Thickness(0, 0, 8, 0) };
        var always = new Button { Content = L("Always", "Luôn dùng"), MinWidth = 90, Padding = new Thickness(8, 4, 8, 4), IsDefault = true };
        once.Click += (s, e) => { Close(); done(_selected); };
        always.Click += (s, e) => { AppSettings.Current.Extractor = _selected; AppSettings.Current.Save(); Close(); done(_selected); };
        buttons.Children.Add(once);
        buttons.Children.Add(always);
        root.Children.Add(buttons);
        root.Children.Add(new TextBlock { Text = L("Change this later in Settings", "Đổi lại sau trong Cài đặt"), FontSize = 11, Foreground = Brushes.Gray, Margin = new Thickness(0, 8, 0, 0) });
        Content = root;
    }
}
