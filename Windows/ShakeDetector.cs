using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace SATF;

public class ShakeDetector : IDisposable
{
    private IntPtr _hookId = IntPtr.Zero;
    private readonly NativeMethods.LowLevelMouseProc _proc;

    private bool _isMouseDown;
    private bool _firedThisHold;
    private int _direction;                 // -1: sang trái, 1: sang phải, 0: chưa rõ
    private int _extremeX;                  // điểm xa nhất theo chiều hiện tại
    private readonly System.Collections.Generic.List<long> _reversals = new();
    private const long WindowMs = 900;      // các lần đổi chiều phải nằm trong khoảng này

    /// Gọi khi phát hiện đủ số lần lắc trong lúc vẫn đang giữ chuột (toạ độ pixel thật).
    public event Action<int, int>? OnShake;

    public ShakeDetector()
    {
        _proc = HookCallback;
    }

    public void Start()
    {
        if (_hookId == IntPtr.Zero)
        {
            using var curProcess = Process.GetCurrentProcess();
            using var curModule = curProcess.MainModule;
            _hookId = NativeMethods.SetWindowsHookEx(
                NativeMethods.WH_MOUSE_LL,
                _proc,
                NativeMethods.GetModuleHandle(curModule?.ModuleName),
                0);
        }
    }

    public void Stop()
    {
        if (_hookId != IntPtr.Zero)
        {
            NativeMethods.UnhookWindowsHookEx(_hookId);
            _hookId = IntPtr.Zero;
        }
    }

    /// Cùng cách nhận diện với bản Mac. Chỉ đọc toạ độ khi đang giữ chuột trái.
    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = wParam.ToInt32();
            if (msg == NativeMethods.WM_LBUTTONDOWN)
            {
                var settings = AppSettings.Current;
                _isMouseDown = settings.ShakeEnabled;
                _firedThisHold = false;
                _direction = 0;
                _reversals.Clear();
                _extremeX = Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam).pt.x;
            }
            else if (msg == NativeMethods.WM_LBUTTONUP)
            {
                _isMouseDown = false;
            }
            else if (msg == NativeMethods.WM_MOUSEMOVE && _isMouseDown && !_firedThisHold)
            {
                Track(Marshal.PtrToStructure<NativeMethods.MSLLHOOKSTRUCT>(lParam).pt);
            }
        }
        return NativeMethods.CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    private void Track(NativeMethods.POINT pt)
    {
        var settings = AppSettings.Current;
        int dx = pt.x - _extremeX;
        long now = Environment.TickCount64;

        if (_direction == 0)
        {
            if (Math.Abs(dx) >= settings.MinSwing) { _direction = dx > 0 ? 1 : -1; _extremeX = pt.x; }
            return;
        }
        if (_direction * dx > 0) { _extremeX = pt.x; return; }   // vẫn đi tiếp cùng chiều
        if (Math.Abs(dx) < settings.MinSwing) return;

        // Đổi chiều đủ xa: tính là một nhịp lắc
        _direction = -_direction;
        _extremeX = pt.x;
        _reversals.Add(now);
        _reversals.RemoveAll(t => now - t > WindowMs);
        if (_reversals.Count < settings.Reversals) return;
        _reversals.Clear();

        int vk = settings.ShakeModifier switch
        {
            ShakeModifier.Shift => NativeMethods.VK_SHIFT,
            ShakeModifier.Ctrl => NativeMethods.VK_CONTROL,
            ShakeModifier.Alt => NativeMethods.VK_MENU,
            _ => 0,
        };
        if (vk != 0 && (NativeMethods.GetAsyncKeyState(vk) & 0x8000) == 0) return;

        _firedThisHold = true;
        int x = pt.x, y = pt.y;
        System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => OnShake?.Invoke(x, y));
    }

    public void Dispose()
    {
        Stop();
        GC.SuppressFinalize(this);
    }
}
