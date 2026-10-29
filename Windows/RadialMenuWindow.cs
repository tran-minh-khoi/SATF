using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Image = System.Windows.Controls.Image;
using Path = System.Windows.Shapes.Path;

namespace SATF;

/// Menu tròn, cùng bố cục với bản Mac:
/// nửa trái = Copy (Chỉ copy / Cất vào khay), nửa phải = Chuyển đổi (vòng ngoài là các định dạng).
/// Góc tính bằng độ, 0° = bên phải, tăng theo chiều kim đồng hồ.
public class RadialMenuWindow : Window
{
    private enum Side { Clipboard, Convert }
    private enum Status { Idle, Working, Done, Failed }
    private record Item(int Id, string Title, string Glyph, string Action, string Format = "");

    // Hình học (giống Mac)
    private const double W = 440, H = 480, CX = 220, CY = 220;
    private const double CenterR = 44, InnerFrom = 52, InnerTo = 118, OuterFrom = 124, OuterTo = 194;
    private const int HalfLimit = 6;   // nửa vòng chứa tối đa 6 ô, nhiều hơn thì ô cuối là "Thêm"

    private readonly List<string> _files = new();
    private readonly List<Item> _clipboardItems = new()
    {
        new(0, "Copy", "", "COPY"),
        new(1, L("Shelf", "Khay"), "", "SHELF"),
    };
    private List<Item> _allConvert = new();

    private Side? _expanded;
    private Side? _hoverSide;
    private int? _hoverItem;
    private bool _showAll;
    private Status _status = Status.Idle;
    private bool _activated;
    private bool _wasDown = true;   // menu mở ra khi đang giữ chuột

    private readonly Grid _root = new() { Width = W, Height = H };
    private readonly Canvas _outer = new() { Width = W, Height = H };
    private readonly Canvas _inner = new() { Width = W, Height = H };
    private readonly Border _centerDisc = new();
    private readonly TextBlock _caption = new() { Foreground = Brushes.White, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 360 };
    private readonly Border _captionPill = new();
    private readonly Dictionary<(Side, int?), (FrameworkElement Group, Path Path, TranslateTransform Push, ScaleTransform LabelScale, TextBlock[] Texts, double Mid, Color Tint)> _segs = new();
    private readonly DispatcherTimer _watch = new() { Interval = TimeSpan.FromMilliseconds(100) };

    public RadialMenuWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        Width = W;
        Height = H;
        AllowDrop = true;

        // Lớp nền trong suốt để nhận chuột/kéo-thả trên cả vùng menu
        _root.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
        _root.Children.Add(_outer);
        _root.Children.Add(_inner);
        BuildCenter();
        BuildCaption();
        Content = _root;

        KeyDown += (s, e) => { if (e.Key == Key.Escape) Close(); };
        Activated += (s, e) => _activated = true;
        Deactivated += (s, e) => { if (_activated && _status == Status.Idle) Close(); };
        DragEnter += OnDrag;
        DragOver += OnDrag;
        DragLeave += (s, e) => ClearHover();
        Drop += OnDrop;
        MouseMove += (s, e) => UpdateHover(e.GetPosition(_root));
        MouseLeave += (s, e) => ClearHover();
        MouseLeftButtonUp += (s, e) => { UpdateHover(e.GetPosition(_root)); Execute(CurrentTarget); };

        // Lắc khi đang bôi đen chữ (không phải kéo file): nhả chuột mà chưa có file nào thì tự đóng
        // Bấm chuột ra ngoài menu thì đóng (kể cả khi menu chưa được chọn làm cửa sổ chính)
        // Đóng menu khi: bấm Esc, thả file ra ngoài, bấm ra ngoài vòng tròn.
        // Dò bằng trạng thái phím/chuột vì lúc kéo file Windows không gửi sự kiện cho cửa sổ này.
        _watch.Tick += (s, e) =>
        {
            bool down = (NativeMethods.GetAsyncKeyState(NativeMethods.VK_LBUTTON) & 0x8000) != 0;
            bool esc = (NativeMethods.GetAsyncKeyState(NativeMethods.VK_ESCAPE) & 0x8000) != 0;
            if (_status == Status.Idle && (esc || (_files.Count == 0 && !down) || (down != _wasDown && CursorOutside()))) Close();
            _wasDown = down;
        };
        Closed += (s, e) => _watch.Stop();
    }

    private bool CursorOutside()
    {
        if (!NativeMethods.GetCursorPos(out var pt)) return false;
        var p = PointFromScreen(new Point(pt.x, pt.y));
        return Math.Sqrt((p.X - CX) * (p.X - CX) + (p.Y - CY) * (p.Y - CY)) > OuterTo + 26;
    }

    /// x, y: toạ độ con trỏ (pixel thật trên màn hình)
    public void ShowAt(int x, int y)
    {
        Rebuild();
        Opacity = 0;
        Show();
        var dpi = VisualTreeHelper.GetDpi(this);
        var area = SystemParameters.WorkArea;
        Left = Math.Clamp(x / dpi.DpiScaleX - CX, area.Left, area.Right - W);
        Top = Math.Clamp(y / dpi.DpiScaleY - CY, area.Top, area.Bottom - H);

        // Hiệu ứng bung ra từ tâm
        var scale = new ScaleTransform(0.6, 0.6, CX, CY);
        _root.RenderTransform = scale;
        var ease = new BackEase { Amplitude = 0.3, EasingMode = EasingMode.EaseOut };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(260)) { EasingFunction = ease });
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(260)) { EasingFunction = ease });
        BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(160)));
        _watch.Start();
        NudgeCursor();
    }

    /// Windows chỉ báo cho menu biết đang kéo file nào khi con trỏ di chuyển trên menu.
    /// Nhích con trỏ 1px rồi trả lại để menu nhận file ngay và hiện đúng icon file, không phải đợi người dùng rê chuột.
    private void NudgeCursor()
    {
        if (!NativeMethods.GetCursorPos(out var start)) return;
        var back = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
        back.Tick += (s, e) =>
        {
            back.Stop();
            // Người dùng đã tự rê chuột đi chỗ khác thì thôi
            if (NativeMethods.GetCursorPos(out var now) && now.x == start.x + 1 && now.y == start.y)
                NativeMethods.SetCursorPos(start.x, start.y);
        };
        Dispatcher.BeginInvoke(DispatcherPriority.Background, () =>
        {
            if (_files.Count > 0 || !NativeMethods.SetCursorPos(start.x + 1, start.y)) return;
            back.Start();
        });
    }

    private void SetFiles(IEnumerable<string> files)
    {
        _files.Clear();
        _files.AddRange(files.Where(File.Exists));
        // Nhiều file: Gộp PDF, các định dạng file nào cũng đổi được, và ZIP (nén chung một file)
        var formats = Converter.GetTargetFormats(_files);
        _allConvert = formats.Select((f, i) => new Item(i, Converter.Label(f), GlyphFor(f), "CONVERT", f)).ToList();
        _showAll = false;
        Rebuild();
    }

    private static string GlyphFor(string format) => format switch
    {
        "JPG" or "PNG" or "WEBP" or "GIF" or "TIFF" or "BMP" => "",
        "MP4" => "",
        "MP3" or "M4A" or "WAV" => "",
        "ZIP" => "",
        "EXTRACT" => "",
        Converter.MergePdf => "\uE8F1",   // Library: chồng tài liệu
        Converter.SplitPdf => "\uE8C6",   // Cut
        _ => "",
    };

    private List<Item> ConvertItems
    {
        get
        {
            if (_showAll || _allConvert.Count <= HalfLimit) return _allConvert;
            return _allConvert.Take(HalfLimit - 1)
                .Append(new Item(HalfLimit - 1, L($"{_allConvert.Count - HalfLimit + 1} more", $"Thêm {_allConvert.Count - HalfLimit + 1}"), "", "MORE"))
                .ToList();
        }
    }

    private List<Item> Items(Side side) => side == Side.Clipboard ? _clipboardItems : ConvertItems;

    private Item? CurrentTarget
    {
        get
        {
            if (_status != Status.Idle || _hoverSide is not Side side) return null;
            if (_hoverItem is int i) { var list = Items(side); return i < list.Count ? list[i] : null; }
            return side == Side.Clipboard ? _clipboardItems[0] : null;   // thả thẳng vào nửa Copy = copy luôn
        }
    }

    // MARK: - Vẽ

    private static (double, double) SideRange(Side side) => side == Side.Convert ? (270, 450) : (90, 270);

    private static (double, double) ItemRange(Side side, int index, int count, bool full)
    {
        if (full) { double s = 360.0 / count; return (270 + index * s, 270 + (index + 1) * s); }
        double span = 180.0 / count;
        if (side == Side.Convert) return (270 + index * span, 270 + (index + 1) * span);
        double end = 270 - index * span;
        return (end - span, end);
    }

    private void Rebuild()
    {
        _segs.Clear();
        _inner.Children.Clear();
        _outer.Children.Clear();

        // Nửa trái chia sẵn 2 ô: Copy ở dưới (90°–180°), Khay ở trên (180°–270°)
        _inner.Children.Add(Segment((Side.Clipboard, 0), (90, 180), InnerFrom, InnerTo, UI.Clipboard, _clipboardItems[0].Title, _clipboardItems[0].Glyph, big: true));
        _inner.Children.Add(Segment((Side.Clipboard, 1), (180, 270), InnerFrom, InnerTo, UI.Clipboard, _clipboardItems[1].Title, _clipboardItems[1].Glyph, big: true));
        _inner.Children.Add(Segment((Side.Convert, null), SideRange(Side.Convert), InnerFrom, InnerTo, UI.Convert, L("Convert", "Chuyển đổi"), "", big: true));

        if (_expanded is Side open && Items(open).Count > 0)
        {
            var list = Items(open);
            bool full = open == Side.Convert && _showAll;
            foreach (var item in list)
            {
                _outer.Children.Add(Segment((open, item.Id), ItemRange(open, item.Id, list.Count, full), OuterFrom, OuterTo,
                    open == Side.Clipboard ? UI.Clipboard : UI.Convert, item.Title, item.Glyph, big: false));
            }
            // Vòng ngoài bung ra
            var scale = new ScaleTransform(0.82, 0.82, CX, CY);
            _outer.RenderTransform = scale;
            var anim = new DoubleAnimation(1, TimeSpan.FromMilliseconds(220)) { EasingFunction = new BackEase { Amplitude = 0.25, EasingMode = EasingMode.EaseOut } };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, anim);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, anim);
            _outer.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)));
        }
        Restyle();
    }

    private FrameworkElement Segment((Side, int?) key, (double, double) range, double inner, double outer,
                                     Color tint, string title, string glyph, bool big)
    {
        var path = new Path { Data = RingGeometry(range.Item1, range.Item2, inner, outer), StrokeThickness = 1 };
        double mid = (range.Item1 + range.Item2) / 2 * Math.PI / 180;
        double r = (inner + outer) / 2;

        var icon = UI.Glyph(glyph, big ? 19 : 15, Brushes.White);
        var text = new TextBlock { Text = title, FontSize = big ? 12 : 11, FontWeight = FontWeights.Bold, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center };
        var label = new StackPanel { IsHitTestVisible = false, RenderTransformOrigin = new Point(0.5, 0.5) };
        label.Children.Add(icon);
        label.Children.Add(text);
        var labelScale = new ScaleTransform(1, 1);
        label.RenderTransform = labelScale;
        label.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        Canvas.SetLeft(label, CX + Math.Cos(mid) * r - label.DesiredSize.Width / 2);
        Canvas.SetTop(label, CY + Math.Sin(mid) * r - label.DesiredSize.Height / 2);

        var group = new Canvas { Width = W, Height = H, IsHitTestVisible = false };
        var push = new TranslateTransform();
        group.RenderTransform = push;
        group.Children.Add(path);
        group.Children.Add(label);
        group.Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 6, ShadowDepth = 2, Opacity = 0.3 };

        _segs[key] = (group, path, push, labelScale, new[] { icon, text }, mid, tint);
        return group;
    }

    /// Hình vành khuyên, chừa khe 3px giữa các ô
    private static Geometry RingGeometry(double start, double end, double inner, double outer)
    {
        const double gap = 3;
        double go = gap / outer * 180 / Math.PI, gi = gap / inner * 180 / Math.PI;
        Point P(double deg, double rad) => new(CX + Math.Cos(deg * Math.PI / 180) * rad, CY + Math.Sin(deg * Math.PI / 180) * rad);
        bool large = end - start > 180;
        var fig = new PathFigure { StartPoint = P(start + go, outer), IsClosed = true };
        fig.Segments.Add(new ArcSegment(P(end - go, outer), new Size(outer, outer), 0, large, SweepDirection.Clockwise, true));
        fig.Segments.Add(new LineSegment(P(end - gi, inner), true));
        fig.Segments.Add(new ArcSegment(P(start + gi, inner), new Size(inner, inner), 0, large, SweepDirection.Counterclockwise, true));
        var g = new PathGeometry();
        g.Figures.Add(fig);
        g.Freeze();
        return g;
    }

    /// Cập nhật màu & hiệu ứng theo trạng thái rê chuột (không vẽ lại hình)
    private void Restyle()
    {
        foreach (var ((side, item), seg) in _segs)
        {
            bool disabled = side == Side.Convert && item == null && ConvertItems.Count == 0;
            bool hovered = _hoverSide == side && _hoverItem == item;
            bool active = item == null && _expanded == side && !hovered;
            var c = seg.Tint;

            seg.Path.Fill = disabled ? new SolidColorBrush(Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF))
                : hovered ? new LinearGradientBrush(Color.FromRgb((byte)Math.Min(255, c.R + 40), (byte)Math.Min(255, c.G + 40), (byte)Math.Min(255, c.B + 40)), c, 90)
                : new SolidColorBrush(Color.FromArgb(active ? (byte)0xE6 : (byte)0xD9, (byte)(0x24 + c.R * (active ? 0.35 : 0.18)), (byte)(0x24 + c.G * (active ? 0.35 : 0.18)), (byte)(0x2C + c.B * (active ? 0.35 : 0.18))));
            seg.Path.Stroke = hovered ? new SolidColorBrush(Color.FromArgb(0x8C, 0xFF, 0xFF, 0xFF)) : new SolidColorBrush(Color.FromArgb(disabled ? (byte)0x1A : (byte)0x73, c.R, c.G, c.B));
            foreach (var t in seg.Texts) t.Foreground = disabled ? UI.Secondary : Brushes.White;

            double push = hovered ? 9 : 0;
            var dur = TimeSpan.FromMilliseconds(160);
            var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };
            seg.Push.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(Math.Cos(seg.Mid) * push, dur) { EasingFunction = ease });
            seg.Push.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(Math.Sin(seg.Mid) * push, dur) { EasingFunction = ease });
            seg.LabelScale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(hovered ? 1.12 : 1, dur));
            seg.LabelScale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(hovered ? 1.12 : 1, dur));
        }
        if (_status != Status.Idle)
        {
            _outer.BeginAnimation(OpacityProperty, null);
            _inner.Opacity = _outer.Opacity = 0.3;
        }
        _caption.Text = Caption();
    }

    private string Caption()
    {
        if (_status == Status.Working) return L("Converting…", "Đang chuyển…");
        if (_status != Status.Idle) return _caption.Text;
        if (_hoverSide is Side side)
        {
            if (_hoverItem is int i && i < Items(side).Count)
            {
                var item = Items(side)[i];
                return item.Action switch
                {
                    "COPY" => "Copy file",
                    "SHELF" => L("Keep on the shelf for later", "Cất vào khay để dùng sau"),
                    "MORE" => L("See all formats", "Xem tất cả định dạng"),
                    _ when item.Format == "EXTRACT" => L("Extract here", "Giải nén tại đây"),
                    _ when item.Format == Converter.MergePdf => L($"Merge {_files.Count} files into one PDF", $"Gộp {_files.Count} file thành một PDF"),
                    _ when item.Format == Converter.SplitPdf => L("One PDF per page", "Tách mỗi trang thành một PDF"),
                    _ when item.Format == "ZIP" && _files.Count > 1 => L($"Compress {_files.Count} files into one ZIP", $"Nén {_files.Count} file thành một ZIP"),
                    _ => L($"Convert to {item.Title}", $"Chuyển sang {item.Title}"),
                };
            }
            if (side == Side.Clipboard) return L("Drop here to copy", "Thả vào đây để copy");
            return ConvertItems.Count == 0 ? L("This file type can't be converted yet", "Loại file này chưa đổi được") : L("Move outward to pick a format", "Rê ra ngoài để chọn định dạng");
        }
        if (_files.Count == 0) return L("Drag a file onto the menu", "Kéo file vào menu");
        return _files.Count == 1 ? System.IO.Path.GetFileName(_files[0]) : L($"{_files.Count} files", $"{_files.Count} file");
    }

    private void BuildCenter()
    {
        _centerDisc.Width = _centerDisc.Height = CenterR * 2;
        _centerDisc.CornerRadius = new CornerRadius(CenterR);
        _centerDisc.Background = UI.Panel;
        _centerDisc.BorderBrush = UI.PanelBorder;
        _centerDisc.BorderThickness = new Thickness(1);
        _centerDisc.HorizontalAlignment = HorizontalAlignment.Left;
        _centerDisc.VerticalAlignment = VerticalAlignment.Top;
        _centerDisc.Margin = new Thickness(CX - CenterR, CY - CenterR, 0, 0);
        _centerDisc.Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 12, ShadowDepth = 2, Opacity = 0.35 };
        _centerDisc.IsHitTestVisible = false;
        _root.Children.Add(_centerDisc);
        UpdateCenter();
    }

    private void UpdateCenter()
    {
        FrameworkElement content = _status switch
        {
            Status.Working => UI.Spinner(34, UI.Convert),
            Status.Done => UI.Glyph("", 36, Brushes.LimeGreen),
            Status.Failed => UI.Glyph("", 30, Brushes.Orange),
            _ => FileIconWithBadge(),
        };
        content.HorizontalAlignment = HorizontalAlignment.Center;
        content.VerticalAlignment = VerticalAlignment.Center;
        _centerDisc.Child = content;
        if (_status is Status.Done or Status.Failed)
        {
            var pop = new ScaleTransform(0.5, 0.5);
            content.RenderTransformOrigin = new Point(0.5, 0.5);
            content.RenderTransform = pop;
            var anim = new DoubleAnimation(1, TimeSpan.FromMilliseconds(260)) { EasingFunction = new BackEase { Amplitude = 0.5, EasingMode = EasingMode.EaseOut } };
            pop.BeginAnimation(ScaleTransform.ScaleXProperty, anim);
            pop.BeginAnimation(ScaleTransform.ScaleYProperty, anim);
        }
    }

    private FrameworkElement FileIconWithBadge()
    {
        var grid = new Grid { Width = 48, Height = 48 };
        if (_files.Count > 0) grid.Children.Add(new Image { Source = UI.FileIcon(_files[0]), Width = 40, Height = 40 });
        else grid.Children.Add(UI.Glyph("\uE8A5", 30, UI.Secondary));   // chưa biết file nào: icon tài liệu chung, không phải logo app
        if (_files.Count > 1)
        {
            grid.Children.Add(new Border
            {
                Background = Brushes.Red, CornerRadius = new CornerRadius(8), Padding = new Thickness(5, 0, 5, 1),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
                Child = new TextBlock { Text = _files.Count.ToString(), Foreground = Brushes.White, FontSize = 10, FontWeight = FontWeights.Bold },
            });
        }
        return grid;
    }

    private void BuildCaption()
    {
        _captionPill.Child = _caption;
        _captionPill.Background = UI.Panel;
        _captionPill.BorderBrush = UI.PanelBorder;
        _captionPill.BorderThickness = new Thickness(1);
        _captionPill.CornerRadius = new CornerRadius(14);
        _captionPill.Padding = new Thickness(12, 5, 12, 6);
        _captionPill.HorizontalAlignment = HorizontalAlignment.Center;
        _captionPill.VerticalAlignment = VerticalAlignment.Bottom;
        _captionPill.Margin = new Thickness(0, 0, 0, 8);
        _captionPill.IsHitTestVisible = false;
        _root.Children.Add(_captionPill);
    }

    // MARK: - Rê chuột

    private void UpdateHover(Point p)
    {
        if (_status != Status.Idle) return;
        double dx = p.X - CX, dy = p.Y - CY;
        double r = Math.Sqrt(dx * dx + dy * dy);
        double angle = Math.Atan2(dy, dx) * 180 / Math.PI;
        if (angle < 0) angle += 360;
        var side = angle >= 90 && angle < 270 ? Side.Clipboard : Side.Convert;

        Side? newSide = null;
        int? newItem = null;
        var newExpanded = _expanded;
        bool newShowAll = _showAll;

        if (side == Side.Clipboard && !_showAll && r >= InnerFrom - 4 && r <= OuterTo + 26)
        {
            newSide = Side.Clipboard;
            newItem = angle < 180 ? 0 : 1;
            newExpanded = null;
        }
        else if (r >= InnerFrom - 4 && r < OuterFrom - 3)
        {
            // Vòng trong: chọn nửa, bung vòng ngoài của nửa đó
            newSide = side;
            if (Items(side).Count > 0) newExpanded = side;
            if (side == Side.Clipboard) newShowAll = false;
        }
        else if (r >= OuterFrom - 3 && r <= OuterTo + 26 && _showAll && _expanded == Side.Convert)
        {
            // Cả vòng tròn đang là định dạng chuyển đổi
            newSide = Side.Convert;
            double span = 360.0 / ConvertItems.Count;
            newItem = Math.Min((int)(((angle - 270 + 360) % 360) / span), ConvertItems.Count - 1);
        }
        else if (r >= OuterFrom - 3 && r <= OuterTo + 26 && Items(side).Count > 0)
        {
            newExpanded = side;
            newSide = side;
            double span = 180.0 / Items(side).Count;
            double raw = side == Side.Convert ? ((angle < 90 ? angle + 360 : angle) - 270) / span : (270 - angle) / span;
            newItem = Math.Clamp((int)raw, 0, Items(side).Count - 1);
        }

        // Rê vào ô "Thêm" -> bung cả vòng tròn
        if (newSide == Side.Convert && newItem is int mi && mi < Items(Side.Convert).Count && Items(Side.Convert)[mi].Action == "MORE")
        {
            newShowAll = true;
            newItem = null;
        }

        bool layoutChanged = newExpanded != _expanded || newShowAll != _showAll;
        bool hoverChanged = newSide != _hoverSide || newItem != _hoverItem;
        _expanded = newExpanded;
        _showAll = newShowAll;
        _hoverSide = newSide;
        _hoverItem = newItem;
        if (layoutChanged) Rebuild();
        else if (hoverChanged) Restyle();
    }

    private void ClearHover()
    {
        if (_hoverSide == null && _hoverItem == null) return;
        _hoverSide = null;
        _hoverItem = null;
        Restyle();
    }

    private void OnDrag(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop)) { e.Effects = DragDropEffects.None; e.Handled = true; return; }
        if (_files.Count == 0 && e.Data.GetData(DataFormats.FileDrop) is string[] files)
        {
            SetFiles(files);
            UpdateCenter();
        }
        e.Effects = DragDropEffects.Copy;
        e.Handled = true;
        UpdateHover(e.GetPosition(_root));
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] files && _files.Count == 0) SetFiles(files);
        UpdateHover(e.GetPosition(_root));
        var target = CurrentTarget;
        if (target != null) { Execute(target); return; }
        // Thả vào giữa: giữ menu lại, bấm chọn sau
        Activate();
    }

    // MARK: - Thực hiện

    private void Execute(Item? item)
    {
        if (item == null || _status != Status.Idle || _files.Count == 0) return;
        switch (item.Action)
        {
            case "COPY":
                var list = new System.Collections.Specialized.StringCollection();
                list.AddRange(_files.ToArray());
                System.Windows.Clipboard.SetFileDropList(list);
                System.Media.SystemSounds.Asterisk.Play();
                Finish(Status.Done, L("Copied", "Đã copy"), 0.8);
                break;

            case "SHELF":
                Close();
                App.Instance.ShelfWindow.AddFiles(_files);
                App.Instance.ShelfWindow.ShowAndActivate();
                break;

            case "MORE":
                _showAll = true;
                Rebuild();
                break;

            case "CONVERT":
                ConvertInBackground(item.Format);
                break;
        }
    }

    private void Finish(Status status, string caption, double closeAfter)
    {
        _status = status;
        _caption.Text = caption;
        UpdateCenter();
        Restyle();
        var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(closeAfter) };
        t.Tick += (s, e) => { t.Stop(); if (IsVisible) Close(); };
        t.Start();
    }

    private void ConvertInBackground(string format)
    {
        var files = _files.ToList();
        // Lần đầu giải nén mà máy có app khác: hỏi dùng app nào
        if (format == "EXTRACT" && AppSettings.Current.Extractor == "" && Archivers.Installed is { Count: > 0 } tools)
        {
            Close();
            ArchiverChooser.Open(tools, tool => Conversion.Run(files, format, slowAfter: 0, tool: tool));
            return;
        }
        // Thiếu gói: hỏi tải, tải xong tự chuyển tiếp
        if (files.Select(f => Converter.RequiredAddOn(f, format)).FirstOrDefault(a => a != null) is AddOn needed)
        {
            Close();
            AddOnsWindow.Open(AddOnsWindow.Reason.Needed, needed, () => Conversion.Run(files, format, slowAfter: 0));
            return;
        }

        _status = Status.Working;
        _hoverSide = null;
        _hoverItem = null;
        UpdateCenter();
        Restyle();
        Conversion.Run(files, format, slowAfter: 1,
            onSlow: () => { if (IsVisible) Close(); },
            onFinish: ok => { if (IsVisible) Finish(ok ? Status.Done : Status.Failed, ok ? L("Done!", "Xong!") : L("Couldn't convert", "Chưa chuyển được"), 0.7); });
    }
}

/// Chuyển file trên thread STA riêng (Office cần STA) và báo kết quả ở góc màn hình.
public static class Conversion
{
    /// Lâu hơn `slowAfter` giây thì hiện "Đang chuyển…" để người dùng làm việc khác.
    public static void Run(List<string> files, string format, double slowAfter, Action? onSlow = null, Action<bool>? onFinish = null, string? tool = null)
    {
        var dispatcher = System.Windows.Application.Current.Dispatcher;
        string what = files.Count == 1 ? System.IO.Path.GetFileName(files[0]) : L($"{files.Count} files", $"{files.Count} file");
        var slow = new DispatcherTimer { Interval = TimeSpan.FromSeconds(Math.Max(slowAfter, 0.01)) };
        slow.Tick += (s, e) =>
        {
            slow.Stop();
            onSlow?.Invoke();
            ToastWindow.Show(Converter.ProgressTitle(format), what, ToastWindow.Style.Working, seconds: null);
        };
        slow.Start();

        var thread = new System.Threading.Thread(() =>
        {
            var created = new List<string>();
            Exception? error = null;
            try { created.AddRange(Converter.ConvertAll(files, format, tool)); }
            catch (Exception ex) { error = ex; Crash.Log(ex); }

            dispatcher.BeginInvoke(() =>
            {
                slow.Stop();
                if (error != null || created.Count == 0)
                {
                    System.Media.SystemSounds.Exclamation.Play();
                    onFinish?.Invoke(false);
                    ToastWindow.Show(L("Couldn't convert", "Chưa chuyển được"), error?.Message ?? "", ToastWindow.Style.Failure, 7);
                    return;
                }
                System.Media.SystemSounds.Asterisk.Play();
                onFinish?.Invoke(true);
                string name = created.Count == 1 ? System.IO.Path.GetFileName(created[0]) : L($"{created.Count} files", $"{created.Count} file");
                ToastWindow.Show(L("Done", "Đã chuyển xong"),
                                 L($"{name} · saved in {UI.FolderName(created[0])}\nClick to show", $"{name} · lưu trong thư mục {UI.FolderName(created[0])}\nBấm để xem"),
                                 ToastWindow.Style.Success, 6, () => UI.RevealInExplorer(created[0]));
            });
        });
        thread.SetApartmentState(System.Threading.ApartmentState.STA);
        thread.IsBackground = true;
        thread.Start();
    }
}
