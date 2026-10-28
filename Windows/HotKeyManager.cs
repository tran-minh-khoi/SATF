using System;
using System.Windows.Interop;

namespace SATF;

/// Phím tắt toàn cục, đọc tổ hợp phím từ Cài đặt.
public class HotKeyManager : IDisposable
{
    private const int HotKeyId = 9000;
    private HwndSource? _source;
    private IntPtr _hwnd = IntPtr.Zero;
    private bool _registered;

    public event Action? OnHotKey;

    public void Attach(IntPtr hwnd)
    {
        _hwnd = hwnd;
        _source = HwndSource.FromHwnd(hwnd);
        _source?.AddHook(HwndHook);
    }

    /// Đăng ký lại theo cài đặt hiện tại. Trả về false nếu phím đã bị app khác dùng.
    public bool Reload(bool suspended = false)
    {
        if (_registered) { NativeMethods.UnregisterHotKey(_hwnd, HotKeyId); _registered = false; }
        var s = AppSettings.Current;
        if (_hwnd == IntPtr.Zero || suspended || !s.HotKeyEnabled) return true;
        _registered = NativeMethods.RegisterHotKey(_hwnd, HotKeyId, s.HotKeyMods | NativeMethods.MOD_NOREPEAT, s.HotKeyVk);
        return _registered;
    }

    private IntPtr HwndHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == NativeMethods.WM_HOTKEY && wParam.ToInt32() == HotKeyId)
        {
            OnHotKey?.Invoke();
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        if (_registered) NativeMethods.UnregisterHotKey(_hwnd, HotKeyId);
        _source?.RemoveHook(HwndHook);
        GC.SuppressFinalize(this);
    }
}
