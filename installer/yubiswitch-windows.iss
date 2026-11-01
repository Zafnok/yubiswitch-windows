; Build with: ISCC.exe installer\yubiswitch-windows.iss (after dotnet build -c Release)
#define AppVersion "1.0.0"

[Setup]
AppId={{A7A7044D-50A8-4130-8D3A-BF13B561E158}
AppName=yubiswitch-windows
AppVersion={#AppVersion}
AppPublisher=Nick Wentz
AppPublisherURL=https://github.com/Zafnok/yubiswitch-windows
DefaultDirName={autopf}\yubiswitch-windows
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
PrivilegesRequired=admin
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
SetupIconFile=..\assets\unlocked.ico
UninstallDisplayIcon={app}\yubiswitch-windows.exe
UninstallDisplayName=yubiswitch-windows
CloseApplications=no
WizardStyle=modern
OutputDir=..\bin\installer
OutputBaseFilename=yubiswitch-windows-setup-{#AppVersion}

[Tasks]
Name: startatlogon; Description: "Start yubiswitch-windows when I log on"

[Files]
Source: "..\bin\Release\yubiswitch-windows.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\bin\Release\yubiswitch-windows.exe.config"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\yubiswitch-windows"; Filename: "{app}\yubiswitch-windows.exe"

; 1.0.0 installed these under the old name. Updates keep the old folder, as with any previous install.
[InstallDelete]
Type: files; Name: "{app}\yubiswitch.exe"
Type: files; Name: "{app}\yubiswitch.exe.config"
Type: files; Name: "{autoprograms}\yubiswitch.lnk"

[Run]
Filename: "{sys}\schtasks.exe"; Parameters: "/delete /tn yubiswitch /f"; Flags: runhidden
; A scheduled task, because the Startup folder can't start an elevated app without a UAC prompt.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ""Register-ScheduledTask yubiswitch-windows -Force -Action (New-ScheduledTaskAction -Execute '{code:TaskExe}') -Trigger (New-ScheduledTaskTrigger -AtLogOn -User '{code:TaskUser}') -User '{code:TaskUser}' -RunLevel Highest -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0)"""; Flags: runhidden; Tasks: startatlogon; StatusMsg: "Setting up start at logon..."
Filename: "{sys}\schtasks.exe"; Parameters: "/delete /tn yubiswitch-windows /f"; Flags: runhidden; Tasks: not startatlogon
; The app requires admin, and postinstall entries otherwise run as the user who started Setup, unelevated.
Filename: "{app}\yubiswitch-windows.exe"; Description: "Start yubiswitch-windows now"; Flags: nowait postinstall runascurrentuser skipifsilent
; A silent update closes the app, so put it back. A silent first install leaves it for the next logon.
Filename: "{app}\yubiswitch-windows.exe"; Flags: nowait; Check: RestartAfterSilentUpdate

[UninstallRun]
; An update keeps 1.0.0's uninstall entries, so these IDs differ from its IDs to stop them replacing these entries.
Filename: "{sys}\taskkill.exe"; Parameters: "/f /im yubiswitch-windows.exe"; Flags: runhidden; RunOnceId: "StopRenamedApp"
Filename: "{app}\yubiswitch-windows.exe"; Parameters: "--unlock"; Flags: runhidden; RunOnceId: "UnlockKeyRenamedApp"
Filename: "{sys}\schtasks.exe"; Parameters: "/delete /tn yubiswitch-windows /f"; Flags: runhidden; RunOnceId: "RemoveRenamedTask"

[Code]
var
  AppWasRunning: Boolean;

function StopApp(ExeName: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im ' + ExeName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  AppWasRunning := StopApp('yubiswitch-windows.exe');
  // 1.0.0 ran under the old name.
  if StopApp('yubiswitch.exe') then
    AppWasRunning := True;
  Result := '';
end;

function RestartAfterSilentUpdate: Boolean;
begin
  Result := WizardSilent and AppWasRunning;
end;

// Apostrophes must be doubled inside PowerShell's single-quoted strings.
function PsQuote(Value: String): String;
begin
  Result := Value;
  StringChangeEx(Result, '''', '''''', True);
end;

function TaskExe(Param: String): String;
begin
  Result := PsQuote(ExpandConstant('{app}\yubiswitch-windows.exe'));
end;

function TaskUser(Param: String): String;
begin
  Result := PsQuote(ExpandConstant('{username}'));
end;
