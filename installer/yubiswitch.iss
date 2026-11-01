; Build with: ISCC.exe installer\yubiswitch.iss (after dotnet build -c Release)
#define AppVersion "1.0.0"

[Setup]
AppId={{A7A7044D-50A8-4130-8D3A-BF13B561E158}
AppName=yubiswitch
AppVersion={#AppVersion}
AppPublisher=Nick Wentz
AppPublisherURL=https://github.com/Zafnok/yubiswitch-windows
DefaultDirName={autopf}\yubiswitch
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
PrivilegesRequired=admin
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
SetupIconFile=..\assets\unlocked.ico
UninstallDisplayIcon={app}\yubiswitch.exe
UninstallDisplayName=yubiswitch
CloseApplications=no
WizardStyle=modern
OutputDir=..\bin\installer
OutputBaseFilename=yubiswitch-setup-{#AppVersion}

[Tasks]
Name: startatlogon; Description: "Start yubiswitch when I log on"

[Files]
Source: "..\bin\Release\yubiswitch.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\bin\Release\yubiswitch.exe.config"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\yubiswitch"; Filename: "{app}\yubiswitch.exe"

[Run]
; A scheduled task, because the Startup folder can't start an elevated app without a UAC prompt.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ""Register-ScheduledTask yubiswitch -Force -Action (New-ScheduledTaskAction -Execute '{code:TaskExe}') -Trigger (New-ScheduledTaskTrigger -AtLogOn -User '{code:TaskUser}') -User '{code:TaskUser}' -RunLevel Highest -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0)"""; Flags: runhidden; Tasks: startatlogon; StatusMsg: "Setting up start at logon..."
Filename: "{sys}\schtasks.exe"; Parameters: "/delete /tn yubiswitch /f"; Flags: runhidden; Tasks: not startatlogon
; The app requires admin, and postinstall entries otherwise run as the user who started Setup, unelevated.
Filename: "{app}\yubiswitch.exe"; Description: "Start yubiswitch now"; Flags: nowait postinstall runascurrentuser skipifsilent
; A silent update closes the app, so put it back. A silent first install leaves it for the next logon.
Filename: "{app}\yubiswitch.exe"; Flags: nowait; Check: RestartAfterSilentUpdate

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/f /im yubiswitch.exe"; Flags: runhidden; RunOnceId: "StopApp"
Filename: "{app}\yubiswitch.exe"; Parameters: "--unlock"; Flags: runhidden; RunOnceId: "UnlockKey"
Filename: "{sys}\schtasks.exe"; Parameters: "/delete /tn yubiswitch /f"; Flags: runhidden; RunOnceId: "RemoveTask"

[Code]
var
  AppWasRunning: Boolean;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  AppWasRunning := Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im yubiswitch.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
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
  Result := PsQuote(ExpandConstant('{app}\yubiswitch.exe'));
end;

function TaskUser(Param: String): String;
begin
  Result := PsQuote(ExpandConstant('{username}'));
end;
