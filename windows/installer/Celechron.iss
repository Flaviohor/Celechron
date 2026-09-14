#define MyAppName "Celechron"
#define MyAppPublisher "nosig"
#define MyAppURL "https://github.com/Flaviohor/Celechron"
#define MyAppExeName "celechron.exe"

#if ArchLabel == "x86"
  #define DestArch "x86compatible"
  #define Install64 ""
#elif ArchLabel == "x64"
  #define DestArch "x64compatible"
  #define Install64 "x64compatible"
#else
  #define DestArch "arm64"
  #define Install64 "arm64"
#endif

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
SourceDir={#SourceRoot}
OutputDir={#SourceRoot}\installer_output
OutputBaseFilename=celechron-{#AppVersion}-{#ArchLabel}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed={#DestArch}
#if Install64 != ""
ArchitecturesInstallIn64BitMode={#Install64}
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "build\windows\{#BuildDir}\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
