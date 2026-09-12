; Celechron Windows x64 安装器脚本（Inno Setup 6）
;
; 打包来源复用 tool/package.py 生成的暂存目录，保证安装版与便携版内容完全一致
; （包含 app-local 部署的 VC++ 运行时，目标机器无需另装运行库）。
;
; 编译：ISCC.exe tool\installer.iss

#define AppName        "Celechron"
#define AppVersion     "1.3.0"
#define AppPublisher   "Celechron contributors"
#define AppURL         "https://github.com/Celechron/Celechron"
#define AppExeName     "Celechron.exe"
#define StageDir       "E:\celechron-windows\dist\Celechron-1.3.0-windows-x64"

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
OutputDir=E:\celechron-windows\dist
OutputBaseFilename={#AppName}-{#AppVersion}-windows-x64-setup
SetupIconFile=E:\celechron-windows\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; 默认按用户安装（不弹 UAC）；也允许用户在向导里改为全机器安装
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
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
