; Portable Flutter output packaged as a normal Windows application.
; The build workflow supplies SourceDir and AppVersion with /D arguments.
#ifndef SourceDir
  #define SourceDir "..\\build\\windows\\x64\\runner\\Release"
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{B7E20A8A-2D5B-4B63-9B6D-AB8C4E5C2F91}
AppName=Absorb Plus
AppVersion={#AppVersion}
AppPublisher=Absorb Plus contributors
AppPublisherURL=https://github.com/atewertfd/absorb-platform
AppSupportURL=https://github.com/atewertfd/absorb-platform/issues
AppUpdatesURL=https://github.com/atewertfd/absorb-platform/releases
DefaultDirName={autopf}\Absorb Plus
DefaultGroupName=Absorb Plus
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
OutputDir=..\build\windows\installer
OutputBaseFilename=Absorb-{#AppVersion}-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\absorb.exe
SetupIconFile=..\windows\runner\resources\app_icon.ico
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=yes
ChangesAssociations=no
; The uninstaller removes only files installed under {app}. Absorb's user
; settings, cache, and downloads are stored outside {app} and are intentionally
; preserved so uninstall/reinstall cannot destroy personal data.

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Registry]
; "Start with Windows" (Settings -> Windows Settings) writes this value itself.
; Nothing is created at install; uninstalling removes the entry so Windows
; does not try to start a removed copy.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Absorb Plus"; Flags: uninsdeletevalue dontcreatekey

[Icons]
Name: "{autodesktop}\Absorb"; Filename: "{app}\absorb.exe"; WorkingDir: "{app}"; IconFilename: "{app}\absorb.exe"
Name: "{group}\Absorb"; Filename: "{app}\absorb.exe"; WorkingDir: "{app}"; IconFilename: "{app}\absorb.exe"

[Run]
Filename: "{app}\absorb.exe"; Description: "Launch Absorb Plus"; Flags: nowait postinstall skipifsilent
