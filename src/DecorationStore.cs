using System;
using System.IO;
using System.Text;

namespace Frostpane
{
    internal static class DecorationStore
    {
        private static string PathFor(string monitor)
        {
            string key=Convert.ToBase64String(Encoding.UTF8.GetBytes(monitor)).TrimEnd('=').Replace('/','_').Replace('+','-');
            return Path.Combine(Preferences.DirectoryName,"decorations",key+".txt");
        }
        internal static string Read(string monitor)
        {
            try {
                var file=new FileInfo(PathFor(monitor));
                if (file.Exists && file.Length<131072) return File.ReadAllText(file.FullName);
            } catch (IOException) { } catch (UnauthorizedAccessException) { }
            return "";
        }
        internal static bool Write(string monitor,string layout)
        {
            try {
                string path=PathFor(monitor);
                if (String.IsNullOrEmpty(layout)) { if (File.Exists(path)) File.Delete(path); return true; }
                Directory.CreateDirectory(Path.GetDirectoryName(path));
                string temp=path+".new";
                File.WriteAllText(temp,layout);
                if (File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path);
                return true;
            } catch (IOException) { return false; } catch (UnauthorizedAccessException) { return false; }
        }
    }
}
