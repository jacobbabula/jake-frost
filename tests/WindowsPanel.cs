using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Forms;

public static class WindowsPanel
{
    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        internal int Left, Top, Right, Bottom;
        internal int Width { get { return Right - Left; } }
        internal int Height { get { return Bottom - Top; } }
        public override string ToString() { return String.Format("({0},{1}) {2}x{3}", Left, Top, Width, Height); }
    }

    private delegate bool WindowVisitor(IntPtr window, IntPtr argument);
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowVisitor visit, IntPtr argument);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out int processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")] private static extern int GetWindowStyle(IntPtr window, int index);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(System.Drawing.Point point);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flag);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int w, int h, uint flags);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    private static IntPtr FindVisible(int processId, string title)
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr window, IntPtr argument) {
            int owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner == processId && IsWindowVisible(window)) {
                var text = new StringBuilder(128);
                GetWindowText(window, text, text.Capacity);
                if (text.ToString() == title) { found = window; return false; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    private static Rect Bounds(IntPtr window)
    {
        Rect rect;
        if (!GetWindowRect(window, out rect)) throw new Exception("The settings window has disappeared.");
        return rect;
    }

    private static void Until(Func<bool> ready, string label, int seconds)
    {
        var clock = Stopwatch.StartNew();
        do {
            if (ready()) return;
            Thread.Sleep(80);
        } while (clock.Elapsed.TotalSeconds < seconds);
        throw new Exception("Timed out waiting for " + label);
    }

    private static AutomationElement Control(IntPtr window, string id)
    {
        AutomationElement control = null;
        Until(delegate {
            var condition = new PropertyCondition(AutomationElement.AutomationIdProperty, id);
            control = AutomationElement.FromHandle(window).FindFirst(TreeScope.Descendants, condition);
            return control != null && !control.Current.IsOffscreen && control.Current.IsEnabled;
        }, id, 8);
        return control;
    }

    private static void Click(IntPtr window, string id)
    {
        ((InvokePattern)Control(window, id).GetCurrentPattern(InvokePattern.Pattern)).Invoke();
    }

    private static void Select(IntPtr window, string id)
    {
        ((SelectionItemPattern)Control(window, id).GetCurrentPattern(SelectionItemPattern.Pattern)).Select();
    }

    private static void CheckSize(IntPtr window, IntPtr monitor, Rect full, bool compact)
    {
        Control(window, compact ? "RestoreButton" : "MinimizeButton");
        Until(delegate {
            Rect now = Bounds(window);
            return compact ? now.Height < full.Height / 2 && now.Width < full.Width
                : Math.Abs(full.Width - now.Width) <= 2 && Math.Abs(full.Height - now.Height) <= 2;
        }, compact ? "compact panel layout" : "restored panel layout", 5);
        Rect current = Bounds(window);
        if (IsIconic(window) || !IsWindowVisible(window) || MonitorFromWindow(window, 2) != monitor ||
            Math.Abs(current.Left - full.Left) > 2 || Math.Abs(current.Top - full.Top) > 2)
            throw new Exception("Panel moved, hid, or minimized to taskbar. Was " + full + ", now " + current);
    }

    private static void CheckDesktopInput(int processId, bool editing)
    {
        IntPtr overlay = FindVisible(processId, "Jake Frost snowfall");
        if (overlay == IntPtr.Zero) throw new Exception("No visible snow overlay.");
        bool clickThrough = (GetWindowStyle(overlay, -20) & 0x20) != 0;
        if (clickThrough == editing) throw new Exception("Unexpected desktop input mode for the snow overlay.");
    }

    private static void CheckButtonOnTop(IntPtr window, string id)
    {
        var bounds = Control(window, id).Current.BoundingRectangle;
        var center = new System.Drawing.Point((int)(bounds.Left + bounds.Width / 2), (int)(bounds.Top + bounds.Height / 2));
        if (GetAncestor(WindowFromPoint(center), 2) != window)
            throw new Exception("Desktop overlays or another window cover the " + id + " button.");
    }

    public static void Run(int processId, string receipt)
    {
        var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        try {
            IntPtr window = IntPtr.Zero;
            Until(delegate { window = FindVisible(processId, "Jake Frost"); return window != IntPtr.Zero; }, "settings window", 10);
            Select(window, "WorkshopTab");
            Control(window, "Tool_Pile");
            var work = Screen.FromHandle(window).WorkingArea;
            int x = work.Left + 18, y = work.Top + 2;
            if (!SetWindowPos(window, IntPtr.Zero, x, y, 0, 0, 0x15)) throw new Exception("Unable to move test panel.");
            Until(delegate { var r = Bounds(window); return Math.Abs(r.Left - x) <= 2 && Math.Abs(r.Top - y) <= 2; }, "non-default panel position", 5);
            Rect full = Bounds(window);
            IntPtr monitor = MonitorFromWindow(window, 2);
            Click(window, "MinimizeButton");
            CheckSize(window, monitor, full, true);
            CheckDesktopInput(processId, false);
            Click(window, "RestoreButton");
            CheckSize(window, monitor, full, false);
            Console.WriteLine("PASS minimize and restore keep the moved Windows panel at its physical position");

            if (!PostMessage(window, 0x0112, new IntPtr(0xF020), IntPtr.Zero)) throw new Exception("SC_MINIMIZE failed.");
            CheckSize(window, monitor, full, true);
            Click(window, "RestoreButton");
            CheckSize(window, monitor, full, false);
            Console.WriteLine("PASS native minimize keeps a visible compact panel on the same monitor");

            Select(window, "Tool_Pile");
            CheckSize(window, monitor, full, true);
            CheckDesktopInput(processId, true);
            CheckButtonOnTop(window, "RestoreButton");
            Click(window, "RestoreButton");
            CheckSize(window, monitor, full, false);
            Select(window, "Tool_Puff");
            CheckSize(window, monitor, full, true);
            Control(window, "DoneButton");
            CheckDesktopInput(processId, true);
            CheckButtonOnTop(window, "DoneButton");
            Until(delegate { return File.Exists(receipt); }, "gift train arrival during desktop play", 150);
            CheckSize(window, monitor, full, true);
            Click(window, "DoneButton");
            CheckSize(window, monitor, full, false);
            CheckDesktopInput(processId, false);
            Console.WriteLine("PASS tool selection, Tools, animated delivery and Done retain the panel anchor");
        } finally {
            if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous);
        }
    }
}
