; Inno Setup script for SgfScrcpy.
; Compiled in CI with:
;   ISCC /DMyVersion=<version> /DMyRoot=<repo-root> windows\sgfscrcpy.iss

#define MyAppName "SgfScrcpy"
#define MyAppExe "sgf_scrcpy.exe"

#ifndef MyVersion
  #define MyVersion "0.0.0"
#endif
#ifndef MyRoot
  #define MyRoot "."
#endif

[Setup]
AppId={{7C1E9A44-4E2B-4C7E-9C2E-9B3A5D6F0A21}}
AppName={#MyAppName}
AppVersion={#MyVersion}
AppPublisher=Mattia Malacarne
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#MyRoot}\dist
OutputBaseFilename=sgfscrcpy-windows-setup-v{#MyVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyRoot}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
