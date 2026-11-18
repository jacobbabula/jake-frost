using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace Frostpane
{
    internal sealed class DesktopMonitor
    {
        public string Id;
        public Rectangle Bounds, Work;
        public double Scale;
    }

    internal static class DesktopMap
    {
        private const int DwmExtendedFrameBounds = 9, DwmCloaked = 14;
        private const int ExStyleIndex = -20, StyleIndex = -16;
        private const int ExToolWindow = 0x80, ExLayered = 0x80000, ExTransparent = 0x20;
        private const int Caption = 0x00C00000;
        private static readonly uint ProcessId = GetCurrentProcessId();
        private static int lastRead;
        private static List<WindowFrame> snapshot;

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect
        {
            public int Left, Top, Right, Bottom;
            public Rectangle Rectangle { get { return Rectangle.FromLTRB(Left, Top, Right, Bottom); } }
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct MonitorInfo
        {
            public int Size;
            public Rect Bounds, Work;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
        }

        private delegate bool MonitorCallback(IntPtr monitor, IntPtr dc, ref Rect bounds, IntPtr data);
        private delegate bool WindowCallback(IntPtr window, IntPtr data);

        [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorCallback visit, IntPtr data);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
        [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint x, out uint y);
        [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback visit, IntPtr data);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")] private static extern bool IsZoomed(IntPtr window);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentProcessId();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int capacity);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] private static extern int GetWindowStyle(IntPtr window, int index);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out Rect bounds);
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out Rect bounds);
        [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr window, ref Point point);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern bool GetLayeredWindowAttributes(IntPtr window, out uint key, out byte alpha, out uint flags);
        [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] private static extern int ReadFrame(IntPtr window, int attribute, out Rect value, int size);
        [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] private static extern int ReadCloak(IntPtr window, int attribute, out int value, int size);

        public static List<DesktopMonitor> Monitors()
        {
            var result = new List<DesktopMonitor>();
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr handle, IntPtr dc, ref Rect bounds, IntPtr data)
            {
                var info = new MonitorInfo { Size = Marshal.SizeOf(typeof(MonitorInfo)) };
                if (!GetMonitorInfo(handle, ref info)) return true;
                uint dpiX, dpiY;
                double scale = GetDpiForMonitor(handle, 0, out dpiX, out dpiY) == 0 && dpiX > 0 ? dpiX / 96.0 : 1;
                result.Add(new DesktopMonitor { Id = info.Device, Bounds = info.Bounds.Rectangle, Work = info.Work.Rectangle, Scale = scale });
                return true;
            }, IntPtr.Zero);
            return result;
        }

        private sealed class WindowFrame
        {
            public string Id;
            public Rectangle Bounds;
            public bool CanHoldSnow;
        }

        private static bool IsShellSurface(string name)
        {
            return name == "Progman" || name == "WorkerW" || name == "Shell_TrayWnd" ||
                   name == "Shell_SecondaryTrayWnd" || name == "SysShadow";
        }

        private static WindowFrame ReadWindow(IntPtr window)
        {
            if (!IsWindowVisible(window) || IsIconic(window)) return null;
            uint pid;
            if (GetWindowThreadProcessId(window, out pid) == 0 || pid == ProcessId) return null;
            int cloaked;
            if (ReadCloak(window, DwmCloaked, out cloaked, 4) == 0 && cloaked != 0) return null;
            int ex = GetWindowStyle(window, ExStyleIndex);
            if ((ex & ExLayered) != 0)
            {
                if ((ex & ExTransparent) != 0) return null;
                uint key, flags;
                byte alpha;
                if (GetLayeredWindowAttributes(window, out key, out alpha, out flags) && (flags & 2) != 0 && alpha == 0) return null;
            }
            Rect rect;
            if (ReadFrame(window, DwmExtendedFrameBounds, out rect, 16) != 0 && !GetWindowRect(window, out rect)) return null;
            if (rect.Right <= rect.Left || rect.Bottom <= rect.Top) return null;
            var name = new StringBuilder(128);
            if (GetClassName(window, name, name.Capacity) == 0) return null;
            string className = name.ToString();
            if (IsShellSurface(className)) return null;
            return new WindowFrame {
                Id = pid.ToString("X", CultureInfo.InvariantCulture)+"-"+window.ToInt64().ToString("X", CultureInfo.InvariantCulture),
                Bounds = rect.Rectangle,
                CanHoldSnow = (ex & ExToolWindow) == 0 && className != "#32768" && className != "tooltips_class32"
            };
        }

        // All monitor overlays on the UI thread share one front-to-back window enumeration per poll.
        private static List<WindowFrame> Frames()
        {
            int now = Environment.TickCount;
            if (snapshot != null && unchecked((uint)(now - lastRead)) < 80) return snapshot;
            var frames = new List<WindowFrame>();
            EnumWindows(delegate(IntPtr window, IntPtr data)
            {
                WindowFrame frame = ReadWindow(window);
                if (frame != null) frames.Add(frame);
                return true;
            }, IntPtr.Zero);
            snapshot = frames;
            lastRead = now;
            return frames;
        }

        private struct Segment
        {
            public int Left, Right;
            public string Anchor;
            public Segment(int left, int right, string anchor) { Left = left; Right = right; Anchor = anchor; }
        }

        private static void Cut(List<Segment> visible, WindowFrame blocker)
        {
            Rectangle b = blocker.Bounds;
            for (int i = visible.Count - 1; i >= 0; i--)
            {
                Segment s = visible[i];
                if (b.Right <= s.Left || b.Left >= s.Right) continue;
                visible.RemoveAt(i);
                if (s.Right > b.Right) visible.Insert(i, new Segment(b.Right, s.Right, blocker.Id));
                if (s.Left < b.Left) visible.Insert(i, new Segment(s.Left, b.Left, s.Anchor));
            }
        }

        public static List<Ledge> Ledges(DesktopMonitor monitor, double effectiveScale)
        {
            return VisibleLedges(Frames(), monitor, effectiveScale);
        }
        internal static List<Rectangle> AppBounds(DesktopMonitor monitor)
        {
            var result=new List<Rectangle>();
            foreach(WindowFrame item in Frames()) {
                Rectangle intersect=Rectangle.Intersect(item.Bounds,monitor.Work);
                if (intersect.Width>0 && intersect.Height>0) result.Add(intersect);
            }
            return result;
        }
        internal static bool WindowAlive(string ledgeId)
        {
            if (String.IsNullOrEmpty(ledgeId)) return false;
            int dash=ledgeId.IndexOf('-'), slash=ledgeId.IndexOf('/');
            if (dash<=0 || slash<=dash+1) return false;
            uint savedPid; long handle;
            if(!UInt32.TryParse(ledgeId.Substring(0,dash),NumberStyles.HexNumber,CultureInfo.InvariantCulture,out savedPid) ||
               !Int64.TryParse(ledgeId.Substring(dash+1,slash-dash-1),NumberStyles.HexNumber,CultureInfo.InvariantCulture,out handle)) return false;
            uint current;
            return (IntPtr.Size==8 || handle==unchecked((int)handle)) && GetWindowThreadProcessId(new IntPtr(handle),out current)!=0 && current==savedPid;
        }

        private static List<Ledge> VisibleLedges(List<WindowFrame> frames, DesktopMonitor monitor, double scale)
        {
            Rectangle work = monitor.Work;
            var result = new List<Ledge>();
            var segments = new List<Segment>();
            int corner = (int)Math.Ceiling(6 * scale);
            for (int i = 0; i < frames.Count; i++)
            {
                WindowFrame frame = frames[i];
                Rectangle r = frame.Bounds;
                if (!frame.CanHoldSnow || r.Width < 56 * scale || r.Height < 32 * scale) continue;
                if (r.Top <= work.Top || r.Top >= work.Bottom) continue;
                int left = Math.Max(work.Left, r.Left + corner), right = Math.Min(work.Right, r.Right - corner);
                if (right <= left) continue;
                segments.Clear();
                segments.Add(new Segment(left, right, "edge"));
                for (int j = 0; j < i && segments.Count > 0; j++)
                {
                    WindowFrame above = frames[j];
                    if (above.Bounds.Top <= r.Top && above.Bounds.Bottom > r.Top) Cut(segments, above);
                }
                foreach (Segment s in segments)
                {
                    if (s.Right - s.Left < 18 * scale) continue;
                    result.Add(new Ledge(frame.Id + "/" + s.Anchor, (s.Left - monitor.Bounds.Left) / scale,
                        (r.Top - monitor.Bounds.Top) / scale, (s.Right - s.Left) / scale));
                }
            }
            return result;
        }

        public static bool Fullscreen(DesktopMonitor monitor)
        {
            IntPtr window = GetForegroundWindow();
            if (window == IntPtr.Zero) return false;
            WindowFrame frame = ReadWindow(window);
            if (frame == null || !frame.CanHoldSnow) return false;
            // A normal maximized window can occupy every pixel if the taskbar auto-hides.
            if (IsZoomed(window) && (GetWindowStyle(window, StyleIndex) & Caption) == Caption) return false;
            Rect client;
            if (!GetClientRect(window, out client)) return false;
            var origin = new Point(client.Left, client.Top);
            if (!ClientToScreen(window, ref origin)) return false;
            Rectangle screen = monitor.Bounds;
            return origin.X <= screen.Left + 1 && origin.Y <= screen.Top + 1 &&
                origin.X + client.Right - client.Left >= screen.Right - 1 &&
                origin.Y + client.Bottom - client.Top >= screen.Bottom - 1;
        }
    }
}
