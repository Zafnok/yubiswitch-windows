# yubiswitch for Windows

A tray icon that stops your YubiKey typing OTP strings when it gets touched by accident. It's
inspired by [yubiswitch](https://github.com/pallotron/yubiswitch) for macOS, but is an unaffiliated
project. Only the keyboard interface is blocked, so FIDO and smart card use keep working while it
is locked.

- Gray key: locked. Green key: unlocked.
- Left-click the icon to lock or unlock. Right-click for the menu.
- It locks at startup, and again 60 seconds after you unlock.
- **Quit unlocks the key.** If the app is killed or the PC shuts down, the key stays as it was, locked or unlocked, until the app next starts and locks it.

Works with any Yubico key (vendor ID `1050`) that has a keyboard interface.

## Install

Run `yubiswitch-setup-<version>.exe`. The wizard has a **Start yubiswitch when I log on** checkbox,
which starts the app at logon with no UAC prompt. It only works if the account you install from is
an administrator and is the one you log on with. Run the wizard again to change that choice.
Uninstalling closes the app, unlocks the key, and removes the logon task.

The app asks for admin rights (UAC) when you start it by hand, because changing device state
requires them. To use a different timer, quit the app, then start it with the number of seconds,
from 1 to 86400:

```bash
yubiswitch.exe 300
```

This only lasts until the app closes. The logon task always uses the default 60 seconds.

## Build

Needs the .NET SDK, and [Inno Setup 6](https://jrsoftware.org/isinfo.php) for the installer. The app
runs on the .NET Framework 4.8 that ships with Windows 10 and 11.

```bash
dotnet build -c Release
```

```bash
ISCC.exe installer\yubiswitch.iss
```

The installer ends up in `bin\installer`. To regenerate the icons, run `tools\make-icons.ps1`.

## How it works

Windows treats keyboards as not disableable: `pnputil /disable-device`, SetupAPI and
`CM_Disable_DevNode` all refuse. So the app sets the `CONFIGFLAG_DISABLED` bit in the keyboard
node's `ConfigFlags` under `HKLM\SYSTEM\CurrentControlSet\Enum\HID\VID_1050&...` and restarts the
device, which then won't start. Unlocking clears the bit and runs `pnputil /enable-device`.

## Limitations

- While locked, anything that needs the OTP keyboard interface won't work, such as `ykman otp calculate` over USB.
- A key plugged into a USB port it hasn't used before shows up as a new, unlocked device. The app locks it as soon as Windows reports the change, so a touch in that brief moment can still type.
- If you stop using the app without using Quit, run it once and choose Quit to restore the key.

## License

[MIT](LICENSE).

This is an independent project. It is not affiliated with or endorsed by the authors of
[yubiswitch for macOS](https://github.com/pallotron/yubiswitch), and it shares no code with that
project. It is also not affiliated with or endorsed by Yubico. YubiKey is a trademark of Yubico.
