using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using Brushes = System.Windows.Media.Brushes;
using Image = System.Windows.Controls.Image;

namespace SATF;

/// Thông tin ủng hộ (giống bản Mac). Mã VietQR (assets/donate-vietqr.png) tạo từ đúng tài khoản này.
public static class Donate
{
    public const string Bank = "MB Bank";
    public const string Account = "0335337802";
    public const string Owner = "Tran Minh Khoi";
    /// Link ủng hộ quốc tế (Ko-fi, Buy Me a Coffee…). null = ẩn nút.
    public static readonly string? InternationalUrl = null;
}

/// Cửa sổ "Ủng hộ SATF": logo, lời cảm ơn, mã VietQR, số tài khoản có nút copy.
public class DonateWindow : Window
{
    private static DonateWindow? _open;

    public static void ShowSingle()
    {
        if (_open == null) { _open = new DonateWindow(); _open.Closed += (s, e) => _open = null; }
        _open.Show();
        _open.Activate();
    }

    private DonateWindow()
    {
        Title = L("Support SATF", "Ủng hộ SATF");
        Width = 360;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Icon = UI.AppIcon;

        var root = new StackPanel { Margin = new Thickness(28, 24, 28, 22) };

        var logo = new Image { Source = UI.AppIcon, Width = 84, Height = 84, RenderTransformOrigin = new Point(0.5, 0.5) };
        var heart = new TextBlock { Text = "", FontFamily = UI.IconFont, FontSize = 20, Foreground = new SolidColorBrush(UI.Donate),
                                    HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, RenderTransformOrigin = new Point(0.5, 0.5) };
        var logoBox = new Grid { Width = 92, Height = 88, HorizontalAlignment = HorizontalAlignment.Center };
        logoBox.Children.Add(logo);
        logoBox.Children.Add(heart);
        root.Children.Add(logoBox);

        root.Children.Add(new TextBlock { Text = L("Support SATF", "Ủng hộ SATF"), FontSize = 18, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 12, 0, 6) });
        root.Children.Add(new TextBlock
        {
            Text = L("SATF is free and open source. If it saves you time, a small coffee keeps it going. Thank you!",
                     "SATF miễn phí và mã nguồn mở. Nếu app giúp bạn tiết kiệm thời gian, một ly cà phê nhỏ sẽ giúp mình làm tiếp. Cảm ơn bạn!"),
            TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, Foreground = Brushes.Gray, FontSize = 12,
        });

        var qr = new Border
        {
            Background = Brushes.White, CornerRadius = new CornerRadius(14), Padding = new Thickness(12), Margin = new Thickness(0, 16, 0, 12),
            HorizontalAlignment = HorizontalAlignment.Center,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 14, ShadowDepth = 3, Opacity = 0.18 },
            Child = new Image { Source = LoadQr(), Width = 190, Height = 190 },
        };
        RenderOptions.SetBitmapScalingMode(qr.Child, BitmapScalingMode.NearestNeighbor);   // QR phải sắc nét để quét
        root.Children.Add(qr);

        root.Children.Add(new TextBlock { Text = L("Scan with any banking app (VietQR)", "Quét bằng app ngân hàng bất kỳ (VietQR)"), FontSize = 11, Foreground = Brushes.Gray, HorizontalAlignment = HorizontalAlignment.Center });
        var accountRow = new StackPanel { Orientation = System.Windows.Controls.Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 2, 0, 0) };
        accountRow.Children.Add(new TextBlock { Text = $"{Donate.Bank} · {Donate.Account}", FontSize = 13, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
        var copy = new Button { Content = "", FontFamily = UI.IconFont, FontSize = 11, Margin = new Thickness(6, 0, 0, 0), Padding = new Thickness(5, 2, 5, 2),
                                Background = Brushes.Transparent, BorderThickness = new Thickness(0), Cursor = System.Windows.Input.Cursors.Hand, ToolTip = L("Copy account number", "Copy số tài khoản") };
        copy.Click += (s, e) =>
        {
            System.Windows.Clipboard.SetText(Donate.Account);
            copy.Content = "";   // dấu ✓
            var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
            t.Tick += (_, _) => { t.Stop(); copy.Content = ""; };
            t.Start();
        };
        accountRow.Children.Add(copy);
        root.Children.Add(accountRow);
        root.Children.Add(new TextBlock { Text = Donate.Owner, FontSize = 11, Foreground = Brushes.Gray, HorizontalAlignment = HorizontalAlignment.Center });

        if (Donate.InternationalUrl is string url)
        {
            var abroad = new Button { Content = L("Support from abroad", "Ủng hộ từ nước ngoài"), Padding = new Thickness(10, 6, 10, 6), Margin = new Thickness(0, 14, 0, 0) };
            abroad.Click += (s, e) => OpenUrl(url);
            root.Children.Add(abroad);
        }

        var star = new TextBlock { Margin = new Thickness(0, 14, 0, 0), HorizontalAlignment = HorizontalAlignment.Center, FontSize = 12 };
        var link = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run(L("Or give SATF a star on GitHub", "Hoặc tặng SATF một ngôi sao trên GitHub")));
        link.Click += (s, e) => OpenUrl("https://github.com/tran-minh-khoi/SATF");
        star.Inlines.Add(link);
        root.Children.Add(star);

        Content = root;

        // Hiện ra: logo nảy nhẹ, trái tim đập
        Loaded += (s, e) =>
        {
            var pop = new ScaleTransform(0.7, 0.7);
            logo.RenderTransform = pop;
            var ease = new BackEase { Amplitude = 0.45, EasingMode = EasingMode.EaseOut };
            pop.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(420)) { EasingFunction = ease });
            pop.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(420)) { EasingFunction = ease });
            var beat = new ScaleTransform(0.9, 0.9);
            heart.RenderTransform = beat;
            var pulse = new DoubleAnimation(0.9, 1.15, TimeSpan.FromMilliseconds(700)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, EasingFunction = new SineEase() };
            beat.BeginAnimation(ScaleTransform.ScaleXProperty, pulse);
            beat.BeginAnimation(ScaleTransform.ScaleYProperty, pulse);
        };
    }

    private static BitmapImage? LoadQr()
    {
        try
        {
            var img = new BitmapImage(new Uri("pack://application:,,,/donate-vietqr.png"));
            img.Freeze();
            return img;
        }
        catch (Exception ex) { Crash.Log(ex); return null; }
    }

    private static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch (Exception ex) { Crash.Log(ex); }
    }
}
