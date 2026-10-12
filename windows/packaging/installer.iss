; Packs the release build into "dist\Usage Monitor Setup <version>.exe".
; make_installer.ps1 passes in the version, build folder and architecture.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef BuildDir
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef Arch
  #define Arch "x64compatible"
#endif
#ifndef Suffix
  #define Suffix ""
#endif

[Setup]
AppId={{74810514-5740-44A9-97D5-A4D53A4AB036}
AppName=Usage Monitor
AppVersion={#AppVersion}
AppPublisher=Usage Monitor contributors
AppPublisherURL=https://github.com/bek-n/usage-monitor
DefaultDirName={autopf}\Usage Monitor
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed={#Arch}
ArchitecturesInstallIn64BitMode={#Arch}
OutputDir=..\..\dist
OutputBaseFilename=Usage Monitor Setup {#AppVersion}{#Suffix}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\UsageMonitor.exe
UninstallDisplayName=Usage Monitor
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=force

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Usage Monitor"; Filename: "{app}\UsageMonitor.exe"
Name: "{autodesktop}\Usage Monitor"; Filename: "{app}\UsageMonitor.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\UsageMonitor.exe"; Description: "{cm:LaunchProgram,Usage Monitor}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/im UsageMonitor.exe /f"; Flags: runhidden; RunOnceId: "StopApp"
Filename: "{sys}\reg.exe"; Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v ""Usage Monitor"" /f"; Flags: runhidden; RunOnceId: "RemoveOpenAtLogin"
