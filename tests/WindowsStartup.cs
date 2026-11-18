using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

// Each trial starts the shipping EXE on a private desktop with its own profile.
// The user's desktop stays selected throughout the benchmark.
public static class WindowsStartup
{
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    private struct StartupInfo {
        internal int size;
        internal string reserved, desktop, title;
        internal int x, y, width, height, columns, rows, attributes, flags;
        internal short show, reservedSize;
        internal IntPtr reservedPtr, stdin, stdout, stderr;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInfo { internal IntPtr process, thread; internal int id, threadId; }
    private delegate bool EnumWindow(IntPtr window, IntPtr data);
    [DllImport("user32", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr mode, int flags, int access, IntPtr security);
    [DllImport("user32")] private static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32")] private static extern bool EnumDesktopWindows(IntPtr desktop, EnumWindow callback, IntPtr data);
    [DllImport("user32")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32")] private static extern int GetWindowThreadProcessId(IntPtr window, out int process);
    [DllImport("user32", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int size);
    [DllImport("user32", SetLastError=true)] private static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr w, IntPtr l, uint flags, uint timeout, out UIntPtr result);
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern bool CreateProcess(string application, StringBuilder command, IntPtr processSecurity, IntPtr threadSecurity,
        bool inherit, uint flags, IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo process);
    [DllImport("kernel32")] private static extern bool CloseHandle(IntPtr handle);

    public static long[] Measure(string exe,string profile)
    {
        if (Process.GetProcessesByName("JakeFrost").Length != 0)
            throw new InvalidOperationException("A copy of Jake Frost is already running. The benchmark leaves it alone.");
        string name = "JakeFrostStartup-" + Guid.NewGuid().ToString("N");
        IntPtr desktop = CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, 0x1FF, IntPtr.Zero);
        if (desktop==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        string previous = Environment.GetEnvironmentVariable("JAKEFROST_SETTINGS_DIR");
        try {
            Directory.CreateDirectory(profile);
            Environment.SetEnvironmentVariable("JAKEFROST_SETTINGS_DIR", profile);
            StartupInfo start = new StartupInfo();
            start.size = Marshal.SizeOf(start); start.desktop = name;
            ProcessInfo info;
            var elapsed = Stopwatch.StartNew();
            if (!CreateProcess(exe,new StringBuilder("\""+exe+"\""),IntPtr.Zero,IntPtr.Zero,false,0,IntPtr.Zero,
                               Path.GetDirectoryName(exe),ref start,out info))
                throw new Win32Exception(Marshal.GetLastWin32Error(),"Unable to launch test copy of "+exe+" (Win32 "+Marshal.GetLastWin32Error()+").");
            try {
                using (var process = Process.GetProcessById(info.id)) {
                    try {
                        long panelTime = -1;
                        while (elapsed.ElapsedMilliseconds < 20000) {
                            if (process.HasExited) throw new InvalidOperationException("App exited before its panel and overlay were ready. Exit "+process.ExitCode);
                            IntPtr panel = IntPtr.Zero, overlay = IntPtr.Zero;
                            EnumDesktopWindows(desktop, delegate(IntPtr window, IntPtr ignored) {
                                int pid;
                                GetWindowThreadProcessId(window,out pid);
                                if(pid!=info.id || !IsWindowVisible(window)) return true;
                                var title=new StringBuilder(64); GetWindowText(window,title,title.Capacity);
                                if(title.ToString()=="Jake Frost") panel=window;
                                if(title.ToString()=="Jake Frost snowfall") overlay=window;
                                return panel==IntPtr.Zero || overlay==IntPtr.Zero;
                            }, IntPtr.Zero);
                            if(panel!=IntPtr.Zero && panelTime<0) panelTime=elapsed.ElapsedMilliseconds;
                            UIntPtr reply;
                            if(panel!=IntPtr.Zero && overlay!=IntPtr.Zero && process.WaitForInputIdle(30) &&
                               SendMessageTimeout(panel,0,IntPtr.Zero,IntPtr.Zero,2,100,out reply)!=IntPtr.Zero)
                                return new long[]{panelTime,elapsed.ElapsedMilliseconds};
                            Thread.Sleep(4);
                        }
                        throw new TimeoutException("The settings window and snow overlay did not become ready on the private desktop.");
                    } finally { if(!process.HasExited) {process.Kill();process.WaitForExit();} }
                }
            } finally {CloseHandle(info.thread); CloseHandle(info.process);}
        } finally {Environment.SetEnvironmentVariable("JAKEFROST_SETTINGS_DIR",previous); CloseDesktop(desktop);}
    }
}
