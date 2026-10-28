using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Brushes = System.Windows.Media.Brushes;
using Image = System.Windows.Controls.Image;
using FontFamily = System.Windows.Media.FontFamily;
using Cursors = System.Windows.Input.Cursors;
using Brush = System.Windows.Media.Brush;
using Path = System.Windows.Shapes.Path;

namespace SATF;

/// Màu, icon, hiệu ứng dùng chung.
public static class UI
{
    public static readonly Color Clipboard = Color.FromRgb(0x38, 0x8F, 0xFF);
    public static readonly Color Convert = Color.FromRgb(0xFF, 0x85, 0x29);
    public static readonly SolidColorBrush Panel = new(Color.FromArgb(0xF2, 0x24, 0x24, 0x2C));
    public static readonly SolidColorBrush PanelBorder = new(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF));
    public static readonly SolidColorBrush Secondary = new(Color.FromRgb(0xA8, 0xA8, 0xB3));
    public static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    private static BitmapSource? _appIcon;
    /// Logo app dạng PNG (WPF không đọc được file .ico chứa ảnh PNG bên trong, từng làm app văng khi mở)
    public static BitmapSource? AppIcon
    {
        get
        {
            if (_appIcon != null) return _appIcon;
            try
            {
                var img = new BitmapImage();
                img.BeginInit();
                img.UriSource = new Uri("pack://application:,,,/AppIcon.png");
                img.CacheOption = BitmapCacheOption.OnLoad;
                img.EndInit();
                img.Freeze();
                _appIcon = img;
            }
            catch (Exception ex) { Crash.Log(ex); }
            return _appIcon;
        }
    }

    /// Icon Windows của file (giống Explorer)
    public static ImageSource? FileIcon(string path)
    {
        try
        {
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (icon == null) return null;
            var src = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            src.Freeze();
            return src;
        }
        catch { return null; }
    }

    /// Vòng xoay "đang xử lý"
    public static FrameworkElement Spinner(double size, Color color)
    {
        var arc = new Path
        {
            Width = size, Height = size,
            Stroke = new SolidColorBrush(color),
            StrokeThickness = size / 9,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            // Dùng định dạng số kiểu Anh: máy để kiểu Việt (1,5) sẽ làm hỏng chuỗi hình vẽ
            Data = Geometry.Parse(FormattableString.Invariant($"M {size / 2},{size / 18} A {size * 4 / 9},{size * 4 / 9} 0 1 1 {size / 18},{size / 2}")),
            RenderTransformOrigin = new Point(0.5, 0.5),
        };
        var rotate = new RotateTransform();
        arc.RenderTransform = rotate;
        rotate.BeginAnimation(RotateTransform.AngleProperty,
            new DoubleAnimation(0, 360, TimeSpan.FromSeconds(0.9)) { RepeatBehavior = RepeatBehavior.Forever });
        return arc;
    }

    public static TextBlock Glyph(string glyph, double size, Brush color) =>
        new() { Text = glyph, FontFamily = IconFont, FontSize = size, Foreground = color, HorizontalAlignment = HorizontalAlignment.Center };

    /// Hiện thư mục chứa file, chọn sẵn file đó
    public static void RevealInExplorer(string path) =>
        System.Diagnostics.Process.Start("explorer.exe", $"/select,\"{path}\"");

    public static string FolderName(string path) =>
        System.IO.Path.GetFileName(System.IO.Path.GetDirectoryName(path)) ?? "";
}

/// Thông báo nhỏ góc dưới-phải màn hình. Chỉ có một cái tại một thời điểm, cái mới thay cái cũ.
public class ToastWindow : Window
{
    public enum Style { Info, Working, Success, Failure }

    private static ToastWindow? _shared;
    private readonly ContentControl _icon = new() { Width = 38, Height = 38, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock _title = new() { Foreground = Brushes.White, FontSize = 13, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _subtitle = new() { Foreground = UI.Secondary, FontSize = 11.5, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0) };
    private readonly TextBlock _chevron = UI.Glyph("", 11, UI.Secondary);
    private Action? _action;
    private int _generation;

    /// `seconds = null`: giữ nguyên tới khi có thông báo khác (dùng cho "Đang chuyển…").
    public static void Show(string title, string subtitle = "", Style style = Style.Info, double? seconds = 4, Action? onClick = null)
    {
        _shared ??= new ToastWindow();
        _shared.Present(title, subtitle, style, seconds, onClick);
    }

    private ToastWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        Width = 344;

        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 8, 0) };
        text.Children.Add(_title);
        text.Children.Add(_subtitle);

        var row = new DockPanel();
        DockPanel.SetDock(_icon, Dock.Left);
        _chevron.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(_chevron, Dock.Right);
        row.Children.Add(_icon);
        row.Children.Add(_chevron);
        row.Children.Add(text);

        var card = new Border
        {
            Child = row,
            Background = UI.Panel,
            BorderBrush = UI.PanelBorder,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(14, 11, 14, 11),
            Margin = new Thickness(12),
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 18, ShadowDepth = 3, Opacity = 0.35 },
            Cursor = Cursors.Arrow,
        };
        Content = card;

        MouseLeftButtonUp += (s, e) => { _action?.Invoke(); Hide(true); };
        card.MouseEnter += (s, e) => { if (_action != null) card.Background = new SolidColorBrush(Color.FromArgb(0xF2, 0x2E, 0x2E, 0x38)); };
        card.MouseLeave += (s, e) => card.Background = UI.Panel;
    }

    private void Present(string title, string subtitle, Style style, double? seconds, Action? onClick)
    {
        _title.Text = title;
        _subtitle.Text = subtitle;
        _subtitle.Visibility = subtitle.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        _action = onClick;
        _chevron.Visibility = onClick != null ? Visibility.Visible : Visibility.Collapsed;
        ((Border)Content).Cursor = onClick != null ? Cursors.Hand : Cursors.Arrow;
        _icon.Content = style switch
        {
            Style.Working => UI.Spinner(28, UI.Convert),
            Style.Success => UI.Glyph("", 30, Brushes.LimeGreen),   // CompletedSolid
            Style.Failure => UI.Glyph("", 28, Brushes.Orange),      // Warning
            _ => new Image { Source = UI.AppIcon },
        };
        var gen = ++_generation;

        if (!IsVisible) { Opacity = 0; Show(); }
        UpdateLayout();
        var area = SystemParameters.WorkArea;
        Left = area.Right - ActualWidth;
        Top = area.Bottom - ActualHeight;
        BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(200)));

        if (seconds is double s)
        {
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(s) };
            timer.Tick += (_, _) => { timer.Stop(); if (gen == _generation) Hide(false); };
            timer.Start();
        }
    }

    private void Hide(bool now)
    {
        var gen = _generation;
        var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(now ? 120 : 350));
        fade.Completed += (s, e) => { if (gen == _generation) base.Hide(); };
        BeginAnimation(OpacityProperty, fade);
    }
}
