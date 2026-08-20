#define MyAppName "SmartMouse Receiver"
#define MyAppVersion "0.5.3"
#define MyAppPublisher "SmartMouse"
#define MyAppExeName "SmartMouseReceiver.exe"

[Setup]
AppId={{B41B511E-6114-49E1-93D0-2F65D3D68CE8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\SmartMouse Receiver
DefaultGroupName={#MyAppName}
OutputDir=installer
OutputBaseFilename=SmartMouseReceiver-Setup-v{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; 生成されるSetup.exe自身にもバージョン情報リソースを持たせる。
; 発行元と版数の分からない実行ファイルは、SmartScreenの評価で不利になる。
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoProductName={#MyAppName}
VersionInfoDescription={#MyAppName} Setup
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
; インストーラーの同意画面にMITライセンスを出す。
LicenseFile=..\LICENSE

[Tasks]
Name: "desktopicon"; Description: "デスクトップにショートカットを作成"; GroupDescription: "追加のショートカット"
Name: "autostart"; Description: "Windowsへのサインイン時に自動で起動"; GroupDescription: "自動起動"

[Files]
; onedirビルドなので、exeと_internalをまとめてインストールする。
Source: "dist\SmartMouseReceiver\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--minimized"; Tasks: autostart

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""SmartMouse Receiver"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes profile=private"; Flags: runhidden
Filename: "{app}\{#MyAppExeName}"; Description: "SmartMouse Receiverを起動"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""SmartMouse Receiver"" program=""{app}\{#MyAppExeName}"""; Flags: runhidden
