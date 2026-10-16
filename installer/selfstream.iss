; Inno Setup script. Build with: iscc /DAppVersion=0.3.0.12 /DSourceDir=<Release folder> installer\selfstream.iss
#ifndef AppVersion
  #define AppVersion "0.0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6D3A41B0-5C0E-4F43-9B52-5E1F0C57A0D1}
AppName=Selfstream
AppVersion={#AppVersion}
AppPublisher=Selfstream
DefaultDirName={autopf}\Selfstream
DefaultGroupName=Selfstream
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=selfstream-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\selfstream.exe
CloseApplications=yes
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Selfstream"; Filename: "{app}\selfstream.exe"
Name: "{autodesktop}\Selfstream"; Filename: "{app}\selfstream.exe"; Tasks: desktopicon

[Run]
; after a normal install: offer to start it
Filename: "{app}\selfstream.exe"; Description: "Start Selfstream"; Flags: nowait postinstall skipifsilent
; after an update started by the app itself (silent): start it again
Filename: "{app}\selfstream.exe"; Flags: nowait runasoriginaluser; Check: WizardSilent
