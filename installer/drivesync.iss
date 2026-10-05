; DriveSync installer (Inno Setup). Built by CI from the Flutter release
; output; run locally with: iscc /DAppVersion=1.0.0 installer\drivesync.iss
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6C5E6B2E-4F0B-4C1F-9C0D-6D1A2B3C4D5E}
AppName=DriveSync
AppVersion={#AppVersion}
AppPublisher=HimanProgrammer
DefaultDirName={localappdata}\Programs\DriveSync
DefaultGroupName=DriveSync
; Per-user install: no admin rights needed.
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=DriveSync-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\drivesync.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "startup"; Description: "Start DriveSync when Windows starts"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\DriveSync"; Filename: "{app}\drivesync.exe"
Name: "{group}\Uninstall DriveSync"; Filename: "{uninstallexe}"
Name: "{userdesktop}\DriveSync"; Filename: "{app}\drivesync.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "DriveSync"; ValueData: """{app}\drivesync.exe"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{app}\drivesync.exe"; Description: "Open DriveSync now"; Flags: nowait postinstall skipifsilent
