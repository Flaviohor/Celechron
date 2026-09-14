; Celechron Windows 安装器脚本（Inno Setup 6）
;
; 一份脚本同时服务本地与 CI，差异全部走命令行 /D 覆盖。
;
; 本地（默认，从 flutter build 产物取文件）：
;   ISCC.exe tool\installer.iss
;
; 本地（推荐：从 tool/package.py 生成的暂存目录取文件，包内已含 app-local
; VC++ 运行库，目标机器无需另装运行库）：
;   ISCC.exe /DStageDir=E:\celechron-windows\dist\Celechron-1.3.0-windows-x64 tool\installer.iss
;
; CI（.github/workflows/build_desktop.yml 调用）：
;   ISCC.exe /DAppVersion=<pubspec 版本> /DArchLabel=x64 /DBuildDir=x64 ^
;            /DSourceRoot=<github.workspace> tool\installer.iss
;
; 可覆盖开关：AppVersion / ArchLabel / BuildDir / SourceRoot / StageDir / OutputDir
; 产物统一落在 {#OutputDir}（默认 installer_output\），文件名
;   Celechron-<版本>-windows-<架构>-setup.exe

#define AppName      "Celechron"
#define AppExeName   "Celechron.exe"
#define AppPublisher "Celechron contributors"
#define AppURL       "https://github.com/Celechron/Celechron"

; ---- 开关默认值：命令行给了就用命令行的（#ifndef 只在未定义时生效）----

#ifndef AppVersion
  #define AppVersion "1.3.0"
#endif

#ifndef ArchLabel
  #define ArchLabel "x64"
#endif

#ifndef BuildDir
  #define BuildDir "x64"
#endif

#ifndef SourceRoot
  ; 本机仓库根目录。CI 通过 /DSourceRoot=${{ github.workspace }} 覆盖，
  ; 所以这里写绝对路径不影响流水线；换机器开发时改这一行即可。
  #define SourceRoot "E:\celechron-windows"
#endif

#ifndef StageDir
  ; 待打包的程序目录：flutter build 的 runner\Release，或含 VC++ 运行库的暂存目录
  #define StageDir SourceRoot + "\build\windows\" + BuildDir + "\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir SourceRoot + "\installer_output"
#endif

; ---- 按目标架构推导 Inno 的架构开关 ----

#if ArchLabel == "x64"
  #define ArchAllowed "x64compatible"
#elif ArchLabel == "arm64"
  #define ArchAllowed "arm64compatible"
#elif ArchLabel == "x86"
  #define ArchAllowed "x86compatible"
#else
  #error ArchLabel 只支持 x64 / arm64 / x86，当前值无法识别
#endif

[Setup]
AppId={{8F1C4E52-3B7A-4D19-9E64-2A7C5B0D83F1}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName} {#AppVersion}
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir={#OutputDir}
OutputBaseFilename={#AppName}-{#AppVersion}-windows-{#ArchLabel}-setup
SetupIconFile={#SourceRoot}\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 默认按用户安装（不弹 UAC）；也允许用户在向导里改为全机器安装
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed={#ArchAllowed}
#if ArchLabel != "x86"
ArchitecturesInstallIn64BitMode={#ArchAllowed}
#endif
MinVersion=10.0.17763
CloseApplications=yes
RestartApplications=no
AllowNoIcons=yes
SetupLogging=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标："; Flags: unchecked
Name: "urlprotocol"; Description: "注册 celechron:// 深链协议（用于桌面小组件跳转付款码）"; GroupDescription: "系统集成："

[Files]
; 整包安装（暂存目录里已含 VC++ 运行时 DLL）
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "使用说明.txt"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\卸载 {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; ---- celechron:// 深链协议 ----
; 桌面端这一项必须由安装器写入注册表，否则 AppLinks 收不到任何事件。
Root: HKA; Subkey: "Software\Classes\celechron"; ValueType: string; ValueName: ""; \
  ValueData: "URL:Celechron Protocol"; Flags: uninsdeletekey; Tasks: urlprotocol
Root: HKA; Subkey: "Software\Classes\celechron"; ValueType: string; ValueName: "URL Protocol"; \
  ValueData: ""; Tasks: urlprotocol
Root: HKA; Subkey: "Software\Classes\celechron\DefaultIcon"; ValueType: string; ValueName: ""; \
  ValueData: "{app}\{#AppExeName},0"; Tasks: urlprotocol
Root: HKA; Subkey: "Software\Classes\celechron\shell\open\command"; ValueType: string; ValueName: ""; \
  ValueData: """{app}\{#AppExeName}"" ""%1"""; Tasks: urlprotocol

[Run]
Filename: "{app}\{#AppExeName}"; Description: "立即运行 {#AppName}"; \
  Flags: nowait postinstall skipifsilent

[Code]
var
  RemoveDataPage: TInputOptionWizardPage;

procedure InitializeWizard();
begin
  RemoveDataPage := CreateInputOptionPage(wpSelectTasks,
    '数据清理设置', '是否在卸载时删除本地数据',
    'Celechron 的数据库保存在「文档」文件夹下（dbuser.hive 等）。' + #13#10 +
    '选择「是」表示卸载本程序时一并删除这些文件（登录信息与本地缓存会丢失，不可恢复）。' + #13#10 +
    '默认保留，卸载后可手动删除。',
    True, False);
  RemoveDataPage.Add('保留我的数据（推荐）');
  RemoveDataPage.Add('卸载时删除上述数据文件');
  RemoveDataPage.Values[0] := True;
end;

function GetRemoveData(): Boolean;
begin
  Result := RemoveDataPage.Values[1];
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Docs: String;
  Names: TArrayOfString;
  I: Integer;
  Found: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    if not GetRemoveData() then Exit;
    ; 记录选择，供 unins000 之后使用
    Docs := ExpandConstant('{userdocs}');
    SetArrayLength(Names, 7);
    Names[0] := 'dbuser.hive';
    Names[1] := 'dboptions.hive';
    Names[2] := 'dbdeadline.hive';
    Names[3] := 'dbflow.hive';
    Names[4] := 'dbfuse.hive';
    Names[5] := 'dbcustomgpa.hive';
    Names[6] := 'dboriginalwebpage.hive';
    Found := 0;
    for I := 0 to GetArrayLength(Names) - 1 do
    begin
      if FileExists(Docs + '\' + Names[I]) then
      begin
        if DeleteFile(Docs + '\' + Names[I]) then
          Found := Found + 1;
      end;
    end;
  end;
end;
