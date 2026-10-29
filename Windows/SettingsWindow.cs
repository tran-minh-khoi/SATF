using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Brushes = System.Windows.Media.Brushes;
using CheckBox = System.Windows.Controls.CheckBox;
using ComboBox = System.Windows.Controls.ComboBox;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using Orientation = System.Windows.Controls.Orientation;

namespace SATF;

/// Cửa sổ Cài đặt: cùng các mục với bản Mac.
public class SettingsWindow : Window
{
    private static SettingsWindow? _open;
    private readonly AppSettings _s = AppSettings.Current;
    private readonly Button _hotKeyButton = new() { MinWidth = 150, Padding = new Thickness(8, 4, 8, 4) };
    private readonly TextBlock _hotKeyError = new() { Foreground = Brushes.IndianRed, FontSize = 11, TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
    private bool _recording;

    public static void ShowSingle()
    {
        if (_open == null) { _open = new SettingsWindow(); _open.Closed += (s, e) => _open = null; }
        _open.Show();
        _open.Activate();
    }

    private SettingsWindow()
    {
        Title = L("SATF Settings", "Cài đặt SATF");
        Width = 440;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Icon = UI.AppIcon;

        var root = new StackPanel { Margin = new Thickness(20) };

        // Đầu trang
        var head = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 16) };
        head.Children.Add(new System.Windows.Controls.Image { Source = UI.AppIcon, Width = 48, Height = 48, Margin = new Thickness(0, 0, 12, 0) });
        var titles = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        titles.Children.Add(new TextBlock { Text = "SATF", FontSize = 16, FontWeight = FontWeights.SemiBold });
        titles.Children.Add(new TextBlock { Text = L("Drag, shake, convert. In a blink.", "Kéo, lắc, đổi file trong nháy mắt"), Foreground = Brushes.Gray });
        head.Children.Add(titles);
        root.Children.Add(head);

        // Ngôn ngữ: đổi xong dựng lại cửa sổ theo ngôn ngữ mới
        var language = Combo(new[] { "English", "Tiếng Việt" }, (int)_s.Language, i => _s.Language = (Language)i);
        language.SelectionChanged += (s, e) => Dispatcher.BeginInvoke(() =>
        {
            var (left, top) = (Left, Top);
            Close();
            ShowSingle();
            _open!.Left = left;
            _open.Top = top;
        });
        root.Children.Add(Section(L("Language", "Ngôn ngữ"), Row(L("Language", "Ngôn ngữ"), language)));

        // Lắc chuột
        var shake = Check(L("Shake while dragging to open the menu", "Lắc file đang kéo để mở menu"), _s.ShakeEnabled, v => _s.ShakeEnabled = v);
        var modifier = Combo(new[] { L("None", "Không cần"), "Shift", "Ctrl", "Alt" }, (int)_s.ShakeModifier, i => _s.ShakeModifier = (ShakeModifier)i);
        // 10 mức: kéo sang trái = lắc nhẹ là mở, sang phải = phải lắc mạnh (đỡ mở nhầm)
        var levelText = new TextBlock { Text = $"{_s.Level}/10", Foreground = Brushes.Gray, MinWidth = 34, TextAlignment = TextAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        var slider = new Slider { Minimum = 1, Maximum = 10, Value = _s.Level, TickFrequency = 1, IsSnapToTickEnabled = true, TickPlacement = System.Windows.Controls.Primitives.TickPlacement.BottomRight, Width = 150, VerticalAlignment = VerticalAlignment.Center };
        slider.ValueChanged += (s, e) => { _s.ShakeLevel = (int)slider.Value; levelText.Text = $"{_s.ShakeLevel}/10"; _s.Save(); };
        var sensitivity = new StackPanel { Orientation = Orientation.Horizontal };
        sensitivity.Children.Add(new TextBlock { Text = L("Light", "Nhẹ"), FontSize = 11, Foreground = Brushes.Gray, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) });
        sensitivity.Children.Add(slider);
        sensitivity.Children.Add(new TextBlock { Text = L("Firm", "Mạnh"), FontSize = 11, Foreground = Brushes.Gray, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 0, 0) });
        sensitivity.Children.Add(levelText);
        root.Children.Add(Section(L("Shake", "Lắc chuột"),
            shake,
            Row(L("Hold key", "Giữ kèm phím"), modifier),
            Row(L("Sensitivity", "Độ nhạy"), sensitivity)));
        void SyncShake() { modifier.IsEnabled = sensitivity.IsEnabled = _s.ShakeEnabled; }
        shake.Click += (s, e) => SyncShake();
        SyncShake();

        // Phím tắt
        _hotKeyButton.Content = _s.HotKeyDisplay;
        _hotKeyButton.Click += (s, e) => StartRecording();
        var hotKey = Check(L("Use keyboard shortcut", "Dùng phím tắt"), _s.HotKeyEnabled, v => _s.HotKeyEnabled = v);
        hotKey.Click += (s, e) => _hotKeyButton.IsEnabled = _s.HotKeyEnabled;
        _hotKeyButton.IsEnabled = _s.HotKeyEnabled;
        root.Children.Add(Section(L("Keyboard shortcut", "Phím tắt"),
            hotKey,
            Row(L("Shortcut", "Tổ hợp phím"), _hotKeyButton),
            _hotKeyError,
            Note(L("While dragging: opens the menu. Otherwise: shows or hides the shelf.", "Đang kéo file: mở menu. Không kéo file: mở hoặc đóng khay."))));

        // Ảnh: mức nén, dung lượng mục tiêu, cỡ khi thu nhỏ
        var levels = new[] { CompressLevel.Light, CompressLevel.Balanced, CompressLevel.Strong };
        var sizes = AppSettings.TargetSizeChoices;
        var edges = AppSettings.ResizeEdgeChoices;
        root.Children.Add(Section(L("Images", "Ảnh"),
            Row(L("Compress", "Nén ảnh"), Combo(levels.Select(AppSettings.LevelLabel).ToArray(), (int)_s.CompressLevel, i => _s.CompressLevel = levels[i])),
            Row(L("Shrink to fit", "Ép dung lượng"), Combo(sizes.Select(k => L("Under ", "Dưới ") + AppSettings.SizeLabel(k)).ToArray(), Math.Max(0, Array.IndexOf(sizes, _s.TargetSizeKB)), i => _s.TargetSizeKB = sizes[i])),
            Row(L("Resize to", "Thu nhỏ còn"), Combo(edges.Select(e => L($"{e}px long side", $"cạnh dài {e}px")).ToArray(), Math.Max(0, Array.IndexOf(edges, _s.ResizeEdge)), i => _s.ResizeEdge = edges[i])),
            Note(L("Edited images are saved as new files. The originals are never changed.", "Ảnh sau khi sửa được lưu thành file mới, ảnh gốc giữ nguyên."))));

        // Tệp nén: chọn app giải nén / nén (hoặc mặc định)
        var tools = Archivers.Installed;
        var extractIds = new System.Collections.Generic.List<string>();
        var extractNames = new System.Collections.Generic.List<string>();
        extractIds.Add(""); extractNames.Add(L("Ask me", "Hỏi mỗi lần"));
        extractIds.Add(Archivers.Builtin); extractNames.Add(L("SATF (built-in)", "SATF (có sẵn)"));
        foreach (var t in tools) { extractIds.Add(t.Id); extractNames.Add(t.Name); }
        var compressIds = new[] { Archivers.Builtin }.Concat(tools.Select(t => t.Id)).ToList();
        var compressNames = new[] { L("SATF (built-in)", "SATF (có sẵn)") }.Concat(tools.Select(t => t.Name)).ToArray();
        var extractor = Combo(extractNames.ToArray(), Math.Max(0, extractIds.IndexOf(_s.Extractor)), i => _s.Extractor = extractIds[i]);
        var compressor = Combo(compressNames, Math.Max(0, compressIds.IndexOf(_s.Compressor)), i => _s.Compressor = compressIds[i]);
        root.Children.Add(Section(L("Archives", "Tệp nén"),
            Row(L("Extract with", "Giải nén bằng"), extractor),
            Row(L("Compress with", "Nén ZIP bằng"), compressor)));

        // Gói tải thêm
        var manage = new Button { Content = L("Manage…", "Quản lý…"), MinWidth = 150, Padding = new Thickness(8, 4, 8, 4) };
        manage.Click += (s, e) => AddOnsWindow.Open();
        root.Children.Add(Section(L("Add-ons", "Gói tải thêm"), Row(L("Office, video & music", "Office, video & nhạc"), manage)));

        // Hệ thống
        root.Children.Add(Section(L("General", "Hệ thống"),
            Check(L("Start with Windows", "Mở cùng Windows"), AppSettings.LaunchAtStartup, v => AppSettings.LaunchAtStartup = v)));

        // Cuộn được và kéo đổi kích thước được: màn hình thấp vẫn xem hết các mục
        MaxHeight = SystemParameters.WorkArea.Height - 40;
        MinWidth = 400;
        MinHeight = 320;
        ResizeMode = ResizeMode.CanResize;
        Content = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        PreviewKeyDown += OnPreviewKeyDown;
        Closed += (s, e) => StopRecording();
        App.Instance.HotKeyFailed += ShowHotKeyError;
        Closed += (s, e) => App.Instance.HotKeyFailed -= ShowHotKeyError;
    }

    private void ShowHotKeyError(bool failed)
    {
        _hotKeyError.Text = L("Another app already uses this shortcut. Try a different one.", "Phím này đã có app khác dùng, chọn phím khác nhé.");
        _hotKeyError.Visibility = failed ? Visibility.Visible : Visibility.Collapsed;
    }

    // MARK: - Ghi phím tắt

    private void StartRecording()
    {
        _recording = true;
        _hotKeyButton.Content = L("Press keys…", "Nhấn tổ hợp phím…");
        App.Instance.SuspendHotKey(true);
    }

    private void StopRecording()
    {
        if (!_recording) return;
        _recording = false;
        _hotKeyButton.Content = _s.HotKeyDisplay;
        App.Instance.SuspendHotKey(false);
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!_recording) return;
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape) { StopRecording(); return; }
        if (key is Key.LeftShift or Key.RightShift or Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin) return;

        var mods = Keyboard.Modifiers;
        // Bắt buộc có Ctrl, Alt hoặc Win để không chiếm phím gõ thường
        if ((mods & (ModifierKeys.Control | ModifierKeys.Alt | ModifierKeys.Windows)) == 0)
        {
            System.Media.SystemSounds.Beep.Play();
            return;
        }
        uint m = 0;
        var parts = new System.Collections.Generic.List<string>();
        if (mods.HasFlag(ModifierKeys.Control)) { m |= NativeMethods.MOD_CONTROL; parts.Add("Ctrl"); }
        if (mods.HasFlag(ModifierKeys.Alt)) { m |= NativeMethods.MOD_ALT; parts.Add("Alt"); }
        if (mods.HasFlag(ModifierKeys.Shift)) { m |= NativeMethods.MOD_SHIFT; parts.Add("Shift"); }
        if (mods.HasFlag(ModifierKeys.Windows)) { m |= NativeMethods.MOD_WIN; parts.Add("Win"); }
        parts.Add(key == Key.Space ? "Space" : new KeyConverter().ConvertToString(key) ?? key.ToString());

        _s.HotKeyMods = m;
        _s.HotKeyVk = (uint)KeyInterop.VirtualKeyFromKey(key);
        _s.HotKeyDisplay = string.Join("+", parts);
        StopRecording();
        _s.Save();
    }

    // MARK: - Khối giao diện

    private CheckBox Check(string text, bool value, Action<bool> set)
    {
        var box = new CheckBox { Content = text, IsChecked = value, Margin = new Thickness(0, 4, 0, 4) };
        box.Click += (s, e) => { set(box.IsChecked == true); _s.Save(); };
        return box;
    }

    private ComboBox Combo(string[] items, int selected, Action<int> set)
    {
        var combo = new ComboBox { ItemsSource = items, SelectedIndex = selected, MinWidth = 150 };
        combo.SelectionChanged += (s, e) => { set(combo.SelectedIndex); _s.Save(); };
        return combo;
    }

    private static FrameworkElement Row(string label, FrameworkElement control)
    {
        var dock = new DockPanel { Margin = new Thickness(0, 4, 0, 4) };
        control.HorizontalAlignment = HorizontalAlignment.Right;
        DockPanel.SetDock(control, Dock.Right);
        dock.Children.Add(control);
        dock.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center });
        return dock;
    }

    private static TextBlock Note(string text) =>
        new() { Text = text, FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) };

    private static FrameworkElement Section(string title, params UIElement[] children)
    {
        var panel = new StackPanel();
        foreach (var c in children) panel.Children.Add(c);
        var wrap = new StackPanel { Margin = new Thickness(0, 0, 0, 14) };
        wrap.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, Foreground = Brushes.Gray, Margin = new Thickness(2, 0, 0, 4) });
        wrap.Children.Add(new Border
        {
            Child = panel,
            Padding = new Thickness(12, 8, 12, 8),
            CornerRadius = new CornerRadius(8),
            Background = new SolidColorBrush(Color.FromArgb(0x0D, 0, 0, 0)),
        });
        return wrap;
    }
}
