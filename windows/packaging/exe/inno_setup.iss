[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; 升级支持：默认即为 yes，此处显式声明以便审计（Inno [Setup] UsePrevious*）
UsePreviousAppDir=yes
UsePreviousTasks=yes
UsePreviousLanguage=yes

[Code]
var
  PrevInstallDetected: Boolean;
  PrevInstallPath: String;
  PrevInstallVersion: String;

procedure KillOldProcess;
var ResultCode: Integer;
begin
  Exec('taskkill', '/F /IM {{EXECUTABLE_NAME}}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function GetPreviousInstallInfo(): Boolean;
var
  Found: Boolean;
begin
  PrevInstallPath := '';
  PrevInstallVersion := '';
  Found := RegQueryStringValue(HKLM, 'Software\WinWin', 'InstallPath', PrevInstallPath);
  if Found and (PrevInstallPath <> '') then
  begin
    RegQueryStringValue(HKLM, 'Software\WinWin', 'Version', PrevInstallVersion);
    Result := True;
  end
  else
    Result := False;
end;

function InitializeSetup(): Boolean;
begin
  KillOldProcess;
  PrevInstallDetected := GetPreviousInstallInfo();
  if PrevInstallDetected then
  begin
    Log('升级探测：检测到已安装的 {{DISPLAY_NAME}} ' + PrevInstallVersion + ' → ' + PrevInstallPath + '（将执行覆盖升级）');
    if not DirExists(PrevInstallPath) then
      Log('升级探测：注意——旧安装目录已不存在，可能被手动删除');
  end
  else
    Log('升级探测：未检测到已安装记录，按全新安装处理');
  Result := True;
end;

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "launchAtStartup"; Description: "{cm:AutoStartProgram,{{DISPLAY_NAME}}}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
; {commonstartup}：与 admin（per-machine）安装模式匹配，消解 Inno「userstartup + admin」告警（上游模板原为 {userstartup}）。
Name: "{commonstartup}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; WorkingDir: "{app}"; Tasks: launchAtStartup

[Registry]
; 升级探测锚点：跨版本读取已安装路径/版本（与 Inno AppId 原生识别互补，不依赖其键名格式）
Root: HKLM; Subkey: "Software\WinWin"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\WinWin"; ValueType: string; ValueName: "Version"; ValueData: "{{APP_VERSION}}"; Flags: uninsdeletevalue
; bilibili:// 协议注册（PiliPlus 模板）仍不启用：WinWin 尚未实现深链 / 单实例接管，待实现后再补。

[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: runascurrentuser nowait postinstall skipifsilent
