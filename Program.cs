using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        // Used by the uninstaller so that removing the app can't leave the key blocked.
        if (args.Length > 0 && args[0] == "--unlock")
        {
            YubiKey.Unlock();
            return;
        }

        int seconds = args.Length > 0 && int.TryParse(args[0], out int s) && s > 0 && s <= 86400 ? s : 60;
        using (new Mutex(true, @"Global\yubiswitch", out bool first))
        {
            if (first) Application.Run(new TrayApp(seconds));
        }
    }
}

// Windows refuses to disable keyboards the normal way (pnputil, SetupAPI and CM_Disable_DevNode all
// fail), so set CONFIGFLAG_DISABLED directly and restart the device so that it fails to start.
// Only the keyboard node is touched; the FIDO and CCID interfaces stay up.
public static class YubiKey
{
    const string HidEnum = @"SYSTEM\CurrentControlSet\Enum\HID";
    const string KeyboardClass = "{4d36e96b-e325-11ce-bfc1-08002be10318}";
    const int ConfigFlagDisabled = 1;
    const uint DnStarted = 0x8;

    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
    static extern uint CM_Locate_DevNodeW(out uint devInst, string id, uint flags);
    [DllImport("cfgmgr32.dll")]
    static extern uint CM_Get_DevNode_Status(out uint status, out uint problem, uint devInst, uint flags);

    // Includes instances for ports the key is not plugged into now, so those stay locked too.
    static List<string> Keyboards()
    {
        var ids = new List<string>();
        using (var hid = Registry.LocalMachine.OpenSubKey(HidEnum))
        {
            foreach (var device in hid.GetSubKeyNames().Where(n => n.StartsWith("VID_1050&", StringComparison.OrdinalIgnoreCase)))
            using (var deviceKey = hid.OpenSubKey(device))
            {
                foreach (var instance in deviceKey.GetSubKeyNames())
                using (var key = deviceKey.OpenSubKey(instance))
                {
                    if (string.Equals(key.GetValue("ClassGUID") as string, KeyboardClass, StringComparison.OrdinalIgnoreCase))
                        ids.Add($@"HID\{device}\{instance}");
                }
            }
        }
        return ids;
    }

    static bool IsPresent(string id) => CM_Locate_DevNodeW(out _, id, 0) == 0;

    static bool IsRunning(string id) =>
        CM_Locate_DevNodeW(out uint node, id, 0) == 0
        && CM_Get_DevNode_Status(out uint status, out _, node, 0) == 0
        && (status & DnStarted) != 0;

    public static bool AnyRunning => Keyboards().Any(IsRunning);

    static void SetDisabledFlag(string id, bool disabled)
    {
        using (var key = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Enum\" + id, true))
        {
            int flags = (int)key.GetValue("ConfigFlags", 0);
            key.SetValue("ConfigFlags", disabled ? flags | ConfigFlagDisabled : flags & ~ConfigFlagDisabled, RegistryValueKind.DWord);
        }
    }

    static void PnpUtil(string command, string id)
    {
        var info = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "pnputil.exe"), $"/{command} \"{id}\"")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
        };
        using (var process = Process.Start(info)) process.WaitForExit();
    }

    public static void Lock()
    {
        foreach (var id in Keyboards())
        {
            SetDisabledFlag(id, true);
            if (IsRunning(id)) PnpUtil("restart-device", id);
        }
    }

    public static void Unlock()
    {
        foreach (var id in Keyboards())
        {
            SetDisabledFlag(id, false);
            if (IsPresent(id)) PnpUtil("enable-device", id);
        }
    }
}

public class TrayApp : ApplicationContext
{
    const int WmDeviceChange = 0x219;
    const int DbtDevNodesChanged = 0x7;
    const uint MsgFltAdd = 1;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern uint RegisterWindowMessageW(string name);
    [DllImport("user32.dll")]
    static extern bool ChangeWindowMessageFilter(uint message, uint flag);

    readonly int seconds;
    readonly NotifyIcon tray = new NotifyIcon();
    readonly Icon lockedIcon = LoadIcon("locked.ico");
    readonly Icon unlockedIcon = LoadIcon("unlocked.ico");
    readonly ToolStripMenuItem toggleItem;
    readonly System.Windows.Forms.Timer autoLock = new System.Windows.Forms.Timer();
    // Device notifications arrive in bursts and must not block, so handle them from a short timer.
    readonly System.Windows.Forms.Timer deviceChanged = new System.Windows.Forms.Timer { Interval = 300 };
    readonly DeviceWatcher watcher;
    bool locked;

    public TrayApp(int seconds)
    {
        // Explorer isn't elevated, so without this its "re-add your icon" message never reaches us.
        ChangeWindowMessageFilter(RegisterWindowMessageW("TaskbarCreated"), MsgFltAdd);

        this.seconds = seconds;
        autoLock.Interval = seconds * 1000;
        autoLock.Tick += (s, e) => SetLocked(true);
        deviceChanged.Tick += (s, e) =>
        {
            deviceChanged.Stop();
            if (locked && YubiKey.AnyRunning) SetLocked(true);
        };
        watcher = new DeviceWatcher(() => { deviceChanged.Stop(); deviceChanged.Start(); });

        var menu = new ContextMenuStrip();
        toggleItem = new ToolStripMenuItem("", null, (s, e) => Toggle());
        menu.Items.Add(toggleItem);
        menu.Items.Add("Quit (unlocks key)", null, (s, e) => Quit());
        tray.ContextMenuStrip = menu;
        tray.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) Toggle(); };
        tray.Icon = lockedIcon;
        tray.Visible = true;

        SetLocked(true);
    }

    public void Toggle() => SetLocked(!locked);

    void SetLocked(bool value)
    {
        locked = value;
        autoLock.Stop();
        try
        {
            if (locked) YubiKey.Lock();
            else YubiKey.Unlock();
        }
        catch (Exception e)
        {
            tray.ShowBalloonTip(5000, "yubiswitch", e.Message, ToolTipIcon.Error);
        }
        if (!locked) autoLock.Start();

        bool failed = locked && YubiKey.AnyRunning;
        if (failed)
            tray.ShowBalloonTip(5000, "yubiswitch", "Could not lock the YubiKey.", ToolTipIcon.Error);

        tray.Icon = locked && !failed ? lockedIcon : unlockedIcon;
        tray.Text = failed ? "YubiKey NOT locked" : locked ? "YubiKey locked" : $"YubiKey unlocked, locks after {seconds}s";
        toggleItem.Text = locked ? "Unlock" : "Lock";
    }

    void Quit()
    {
        autoLock.Stop();
        deviceChanged.Stop();
        locked = false;
        YubiKey.Unlock();
        tray.Visible = false;
        Application.Exit();
    }

    static Icon LoadIcon(string name)
    {
        using (var stream = typeof(TrayApp).Assembly.GetManifestResourceStream(name))
            return new Icon(stream, SystemInformation.SmallIconSize);
    }

    class DeviceWatcher : NativeWindow
    {
        readonly Action changed;

        public DeviceWatcher(Action changed)
        {
            this.changed = changed;
            CreateHandle(new CreateParams());
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WmDeviceChange && (int)m.WParam == DbtDevNodesChanged) changed();
            base.WndProc(ref m);
        }
    }
}
