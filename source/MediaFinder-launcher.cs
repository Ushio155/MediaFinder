using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using System.Windows.Forms;

class MediaFinderLauncher
{
    static readonly string[][] Resources = new string[][] {
        new[]{"MF.MediaFinder.Core.ps1","MediaFinder.Core.ps1"},
        new[]{"MF.MediaFinder-thumb.ps1","MediaFinder-thumb.ps1"},
        new[]{"MF.MediaFinder.ps1","MediaFinder.ps1"},
        new[]{"MF.MediaFinderServer.ps1","MediaFinderServer.ps1"},
        new[]{"MF.Everything.exe","Everything.exe"},
        new[]{"MF.Everything64.dll","Everything64.dll"},
        new[]{"MF.MediaFinder.cmd","MediaFinder.cmd"},
        new[]{"MF.THIRD-PARTY.txt","THIRD-PARTY.txt"},
        new[]{"MF.MediaFinder-README.txt","使用说明.txt"},
        new[]{"MF.MediaFinder-web.cmd","MediaFinder-web.cmd"},
        new[]{"MF.MediaFinder-web.vbs","MediaFinder-web.vbs"},
        new[]{"MF.MediaFinder-web-visible.cmd","MediaFinder-web-visible.cmd"},
        new[]{"MF.MediaFinder-stop.cmd","MediaFinder-stop.cmd"},
        new[]{"MF.MediaFinder.config.json","MediaFinder.config.json"},
        new[]{"MF.MediaFinder.ico","MediaFinder.ico"},
        new[]{"MF.web.index.html","web\\index.html"},
        new[]{"MF.web.style.css","web\\style.css"},
        new[]{"MF.web.app.js","web\\app.js"},
    };

    [STAThread]
    static void Main()
    {
        try
        {
            string appDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MediaFinder");
            Directory.CreateDirectory(appDir);
            Directory.CreateDirectory(Path.Combine(appDir, "web"));
            ExtractResources(appDir);
            CreateShortcut(appDir);
            StartServer(appDir);
        }
        catch (Exception ex)
        {
            MessageBox.Show("MediaFinder 启动失败：\n" + ex.Message, "MediaFinder", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    static void ExtractResources(string appDir)
    {
        Assembly asm = Assembly.GetExecutingAssembly();
        foreach (string[] res in Resources)
        {
            string name = res[0];
            string rel = res[1];
            string target = Path.Combine(appDir, rel);
            if (rel == "MediaFinder.config.json" && File.Exists(target)) continue;
            try
            {
                using (Stream s = asm.GetManifestResourceStream(name))
                {
                    if (s == null) continue;
                    using (FileStream fs = new FileStream(target, FileMode.Create, FileAccess.Write))
                    {
                        s.CopyTo(fs);
                    }
                }
            }
            catch { }
        }
    }

    static void CreateShortcut(string appDir)
    {
        string targetCmd = Path.Combine(appDir, "MediaFinder-web.cmd");
        string ico = Path.Combine(appDir, "MediaFinder.ico");
        string desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        string lnk = Path.Combine(desktop, "MediaFinder.lnk");
        try
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            dynamic shell = Activator.CreateInstance(t);
            dynamic sc = shell.CreateShortcut(lnk);
            sc.TargetPath = targetCmd;
            sc.WorkingDirectory = appDir;
            sc.Description = "MediaFinder 媒体查找工具";
            if (File.Exists(ico)) sc.IconLocation = ico + ",0";
            sc.Save();
        }
        catch { }
    }

    static void StartServer(string appDir)
    {
        string server = Path.Combine(appDir, "MediaFinderServer.ps1");
        string args = string.Format("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{0}\"", server);
        try
        {
            Process.Start("powershell.exe", args);
        }
        catch { }
    }
}
