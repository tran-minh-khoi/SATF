using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using ContextMenu = System.Windows.Controls.ContextMenu;
using MenuItem = System.Windows.Controls.MenuItem;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;

namespace SATF;

public class ShelfItem
{
    public string Path { get; set; } = "";
    public string Name => System.IO.Path.GetFileName(Path);
    public ImageSource? Icon { get; set; }
}

/// Khay: cùng cách dùng với bản Mac. Bấm / Ctrl-bấm / Shift-bấm để chọn, Ctrl+A chọn tất cả,
/// Delete bỏ file khỏi khay, kéo một file đang chọn = kéo cả nhóm, bấm đúp để mở.
public partial class ShelfWindow : Window
{
    private readonly ObservableCollection<ShelfItem> _items = new();
    private Point _dragStart;
    private bool _dragging;
    /// Bấm vào file đã chọn (không giữ phím): chưa bỏ chọn nhóm vội, để còn kéo cả nhóm. Nhả chuột mà không kéo thì mới chọn riêng file đó.
    private ShelfItem? _pendingSelect;

    public ShelfWindow()
    {
        InitializeComponent();
        FileListBox.ItemsSource = _items;
        _items.CollectionChanged += (s, e) => Refresh();

        TitleBar.MouseLeftButtonDown += (s, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };
        PreviewKeyDown += OnKey;
        FileListBox.ContextMenuOpening += OnContextMenu;
        FileListBox.ContextMenu = new ContextMenu();   // nội dung tạo lúc mở

        Refresh();
        ApplyLanguage();
        AppSettings.Changed += ApplyLanguage;
    }

    private void ApplyLanguage()
    {
        TitleText.Text = L("Shelf", "Khay");
        EmptyTitle.Text = L("Drop files here", "Kéo file vào đây");
        DragAllButton.ToolTip = L("Drag to take all files", "Kéo để mang tất cả file đi");
        CopyAllButton.ToolTip = L("Copy all", "Copy tất cả");
        ClearButton.ToolTip = L("Clear shelf", "Dọn khay");
        CloseButton.ToolTip = L("Close", "Đóng khay");
        Refresh();
    }

    private void Refresh()
    {
        bool empty = _items.Count == 0;
        EmptyPlaceholder.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        CountBadge.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        CountText.Text = _items.Count.ToString();
        DragAllButton.IsEnabled = CopyAllButton.IsEnabled = ClearButton.IsEnabled = !empty;

        int selected = FileListBox.SelectedItems.Count;
        HintText.Text = selected > 1 ? L($"{selected} selected · drag to move them together", $"Đã chọn {selected} file · kéo để mang đi cùng lúc")
            : _items.Count > 1 ? L("Ctrl+A selects all · drag files out to use them", "Ctrl+A chọn tất cả · kéo file ra ngoài để dùng")
            : L("Drag files out to use them", "Kéo file ra ngoài để dùng");
        HintText.Foreground = UI.Secondary;
    }

    private void Flash(string text)
    {
        HintText.Text = text;
        HintText.Foreground = new SolidColorBrush(UI.Edit);
        var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.4) };
        t.Tick += (s, e) => { t.Stop(); Refresh(); };
        t.Start();
    }

    public void AddFiles(IEnumerable<string> filePaths)
    {
        foreach (var p in filePaths)
        {
            if ((File.Exists(p) || Directory.Exists(p)) && !_items.Any(i => i.Path.Equals(p, StringComparison.OrdinalIgnoreCase)))
            {
                _items.Add(new ShelfItem { Path = p, Icon = UI.FileIcon(p) });
                // File mới vào khay: phóng nhẹ từ nhỏ lên
                Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, () => PopIn(_items[^1]));
            }
        }
    }

    private void PopIn(ShelfItem item)
    {
        if (FileListBox.ItemContainerGenerator.ContainerFromItem(item) is not ListBoxItem c) return;
        var scale = new ScaleTransform(0.6, 0.6);
        c.RenderTransform = scale;
        var ease = new BackEase { Amplitude = 0.4, EasingMode = EasingMode.EaseOut };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(260)) { EasingFunction = ease });
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(260)) { EasingFunction = ease });
        c.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(180)));
    }

    public void ShowAndActivate()
    {
        bool wasHidden = !IsVisible;
        Show();
        Activate();
        if (!wasHidden) return;
        // Hiện ra: mờ dần + phóng nhẹ
        var scale = (ScaleTransform)Card.RenderTransform;
        var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(0.94, 1, TimeSpan.FromMilliseconds(200)) { EasingFunction = ease });
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(0.94, 1, TimeSpan.FromMilliseconds(200)) { EasingFunction = ease });
        BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)));
    }

    public void Toggle()
    {
        if (IsVisible) Hide(); else ShowAndActivate();
    }

    private List<string> SelectedPaths() =>
        _items.Where(i => FileListBox.SelectedItems.Contains(i)).Select(i => i.Path).ToList();   // giữ thứ tự trong khay

    private void Remove(IEnumerable<string> paths)
    {
        foreach (var p in paths.ToList())
            if (_items.FirstOrDefault(i => i.Path == p) is { } item) _items.Remove(item);
    }

    // MARK: - Bàn phím

    private void OnKey(object sender, System.Windows.Input.KeyEventArgs e)
    {
        bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
        if (ctrl && e.Key == Key.A) { FileListBox.SelectAll(); e.Handled = true; }
        else if (e.Key is Key.Delete or Key.Back && FileListBox.SelectedItems.Count > 0) { Remove(SelectedPaths()); e.Handled = true; }
        else if (e.Key == Key.Escape)
        {
            if (FileListBox.SelectedItems.Count > 0) FileListBox.UnselectAll(); else Hide();
            e.Handled = true;
        }
    }

    // MARK: - Nút

    private void OnCloseClick(object sender, RoutedEventArgs e) => Hide();

    private void OnCopyAllClick(object sender, RoutedEventArgs e)
    {
        if (_items.Count == 0) return;
        var sc = new System.Collections.Specialized.StringCollection();
        sc.AddRange(_items.Select(i => i.Path).ToArray());
        System.Windows.Clipboard.SetFileDropList(sc);
        Flash(L($"Copied {_items.Count} files", $"Đã copy {_items.Count} file"));
    }

    private void OnClearAllClick(object sender, RoutedEventArgs e) => _items.Clear();

    private void OnSelectionChanged(object sender, SelectionChangedEventArgs e) => Refresh();

    // MARK: - Thả file vào khay

    private void OnListDragOver(object sender, DragEventArgs e)
    {
        if (_dragging || !e.Data.GetDataPresent(DataFormats.FileDrop)) { e.Effects = DragDropEffects.None; e.Handled = true; return; }
        e.Effects = DragDropEffects.Copy;
        e.Handled = true;
        DropBorder.Stroke = new SolidColorBrush(UI.Clipboard);
        DropZone.Background = new SolidColorBrush(Color.FromArgb(0x1E, UI.Clipboard.R, UI.Clipboard.G, UI.Clipboard.B));
    }

    private void OnListDragLeave(object sender, DragEventArgs e) => ResetDropZone();

    private void ResetDropZone()
    {
        DropBorder.Stroke = new SolidColorBrush(Color.FromArgb(0x55, 0xFF, 0xFF, 0xFF));
        DropZone.Background = new SolidColorBrush(Color.FromArgb(0x08, 0xFF, 0xFF, 0xFF));
    }

    private void OnListDrop(object sender, DragEventArgs e)
    {
        ResetDropZone();
        if (!_dragging && e.Data.GetData(DataFormats.FileDrop) is string[] files) AddFiles(files);
    }

    // MARK: - Chọn & kéo file ra ngoài

    private ShelfItem? ItemAt(MouseEventArgs e) =>
        (e.OriginalSource as DependencyObject) is { } d && ItemsControl.ContainerFromElement(FileListBox, d) is ListBoxItem c ? c.DataContext as ShelfItem : null;

    private void OnListPreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        _dragStart = e.GetPosition(null);
        _pendingSelect = null;
        var item = ItemAt(e);
        if (item == null) { if (e.ClickCount == 1) FileListBox.UnselectAll(); return; }   // bấm chỗ trống: bỏ chọn
        if (Keyboard.Modifiers == ModifierKeys.None && FileListBox.SelectedItems.Contains(item) && FileListBox.SelectedItems.Count > 1 && e.ClickCount == 1)
        {
            _pendingSelect = item;
            e.Handled = true;
        }
    }

    private void OnListPreviewMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (_pendingSelect != null) { FileListBox.SelectedItems.Clear(); FileListBox.SelectedItem = _pendingSelect; }
        _pendingSelect = null;
    }

    private void OnListMouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || _dragging || !MovedEnough(e)) return;
        var item = _pendingSelect ?? ItemAt(e);
        if (item == null) return;
        _pendingSelect = null;
        var paths = FileListBox.SelectedItems.Contains(item) ? SelectedPaths() : [item.Path];
        StartDrag(paths);
    }

    private void OnDragAllDown(object sender, MouseButtonEventArgs e) { _dragStart = e.GetPosition(null); e.Handled = true; }

    private void OnDragAllMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed && !_dragging && _items.Count > 0 && MovedEnough(e))
            StartDrag(_items.Select(i => i.Path).ToList());
    }

    private bool MovedEnough(MouseEventArgs e)
    {
        var d = _dragStart - e.GetPosition(null);
        return Math.Abs(d.X) > SystemParameters.MinimumHorizontalDragDistance || Math.Abs(d.Y) > SystemParameters.MinimumVerticalDragDistance;
    }

    private void StartDrag(List<string> paths)
    {
        _dragging = true;   // không tự thả lại vào chính khay
        try { DragDrop.DoDragDrop(FileListBox, new DataObject(DataFormats.FileDrop, paths.ToArray()), DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link); }
        finally { _dragging = false; }
    }

    private void OnListDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (ItemAt(e) is { } item) Open(item.Path);
    }

    private static void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch (Exception ex) { Crash.Log(ex); }
    }

    private void OnContextMenu(object sender, ContextMenuEventArgs e)
    {
        var paths = SelectedPaths();
        if (paths.Count == 0) { e.Handled = true; return; }
        var menu = FileListBox.ContextMenu!;
        menu.Items.Clear();
        void Add(string title, Action run) { var mi = new MenuItem { Header = title }; mi.Click += (s, a) => run(); menu.Items.Add(mi); }
        Add(L("Open", "Mở"), () => paths.ForEach(Open));
        Add(L("Show in Explorer", "Hiện trong Explorer"), () => UI.RevealInExplorer(paths[0]));
        menu.Items.Add(new Separator());
        Add(paths.Count > 1 ? L($"Remove {paths.Count} from shelf", $"Bỏ {paths.Count} file khỏi khay") : L("Remove from shelf", "Bỏ khỏi khay"), () => Remove(paths));
    }
}
