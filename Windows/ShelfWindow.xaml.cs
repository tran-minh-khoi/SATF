using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media.Imaging;

namespace SATF;

public class ShelfItem
{
    public string Path { get; set; } = "";
    public string Name => System.IO.Path.GetFileName(Path);
}

public partial class ShelfWindow : Window
{
    private readonly ObservableCollection<ShelfItem> _items = new();
    private Point _dragStartPoint;

    public ShelfWindow()
    {
        InitializeComponent();
        FileListBox.ItemsSource = _items;

        MouseLeftButtonDown += (s, e) =>
        {
            if (e.ButtonState == MouseButtonState.Pressed)
            {
                DragMove();
            }
        };

        UpdatePlaceholder();
        LoadLogo();
        ApplyLanguage();
        AppSettings.Changed += ApplyLanguage;
    }

    private void ApplyLanguage()
    {
        TitleText.Text = L("Shelf", "Khay");
        EmptyTitle.Text = L("Drop files here", "Kéo file vào đây");
        EmptyHint.Text = L("Drag files out to use them", "Kéo ra ngoài để dùng");
        CopyAllButton.Content = L("Copy all", "Copy tất cả");
        ClearButton.Content = L("Clear", "Dọn khay");
    }

    private void LoadLogo() => AppLogo.Source = UI.AppIcon;

    public void AddFiles(System.Collections.Generic.IEnumerable<string> filePaths)
    {
        foreach (var p in filePaths)
        {
            if (File.Exists(p) && !_items.Any(i => i.Path.Equals(p, StringComparison.OrdinalIgnoreCase)))
            {
                _items.Add(new ShelfItem { Path = p });
            }
        }
        UpdatePlaceholder();
    }

    public void ShowAndActivate()
    {
        Show();
        Activate();
    }

    public void Toggle()
    {
        if (IsVisible)
        {
            Hide();
        }
        else
        {
            ShowAndActivate();
        }
    }

    private void UpdatePlaceholder()
    {
        EmptyPlaceholder.Visibility = _items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnCloseClick(object sender, RoutedEventArgs e) => Hide();

    private void OnRemoveFileClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string path)
        {
            var item = _items.FirstOrDefault(i => i.Path == path);
            if (item != null)
            {
                _items.Remove(item);
                UpdatePlaceholder();
            }
        }
    }

    private void OnCopyAllClick(object sender, RoutedEventArgs e)
    {
        if (_items.Count > 0)
        {
            var sc = new System.Collections.Specialized.StringCollection();
            sc.AddRange(_items.Select(i => i.Path).ToArray());
            System.Windows.Clipboard.SetFileDropList(sc);
            System.Media.SystemSounds.Asterisk.Play();
        }
    }

    private void OnClearAllClick(object sender, RoutedEventArgs e)
    {
        _items.Clear();
        UpdatePlaceholder();
    }

    private void OnListDragOver(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            e.Effects = DragDropEffects.Copy;
            e.Handled = true;
        }
    }

    private void OnListDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files)
            {
                AddFiles(files);
            }
        }
    }

    private void OnListPreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        _dragStartPoint = e.GetPosition(null);
    }

    private void OnListMouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
        {
            Point current = e.GetPosition(null);
            Vector diff = _dragStartPoint - current;

            if (Math.Abs(diff.X) > SystemParameters.MinimumHorizontalDragDistance ||
                Math.Abs(diff.Y) > SystemParameters.MinimumVerticalDragDistance)
            {
                if (FileListBox.SelectedItem is ShelfItem selected)
                {
                    var data = new DataObject(DataFormats.FileDrop, new string[] { selected.Path });
                    DragDrop.DoDragDrop(FileListBox, data, DragDropEffects.Copy);
                }
            }
        }
    }
}
