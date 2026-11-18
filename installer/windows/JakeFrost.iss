; Run BuildSetup.ps1 after building the app. Its payload and version come from that build.
#define GiftProgId "JakeFrost.Gift"
#define ClassesKey "Software\Classes"

[Setup]
AppId=JakeFrost.Desktop
AppName=Jake Frost
AppVersion={#AppVersion}
AppPublisher=Jake Frost
AppPublisherURL=https://github.com/jacobbabula/jake-frost
DefaultDirName={localappdata}\Programs\Jake Frost
PrivilegesRequired=lowest
MinVersion=10.0
AppMutex=Local\JakeFrost.Desktop.v3
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableFinishedPage=yes
DisableStartupPrompt=yes
UninstallDisplayIcon={app}\JakeFrost.exe
SetupIconFile=..\..\src\JakeFrost.ico
OutputBaseFilename=Jake-Frost-Setup
Compression=lzma2
SolidCompression=yes
ChangesAssociations=yes
VersionInfoVersion={#FileVersion}
VersionInfoProductName=Jake Frost
VersionInfoDescription=Jake Frost for Windows
WizardStyle=modern

[Files]
Source: "{#AppDirectory}\JakeFrost.exe"; DestDir: "{app}"
Source: "{#AppDirectory}\JakeFrost.exe.config"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\Jake Frost"; Filename: "{app}\JakeFrost.exe"; WorkingDir: "{app}"

[Registry]
Root: HKCU; Subkey: "{#ClassesKey}\{#GiftProgId}"; ValueType: string; ValueData: "Jake Frost gift"; Flags: uninsdeletekey
Root: HKCU; Subkey: "{#ClassesKey}\{#GiftProgId}\DefaultIcon"; ValueType: string; ValueData: """{app}\JakeFrost.exe"",0"
Root: HKCU; Subkey: "{#ClassesKey}\{#GiftProgId}\shell\open\command"; ValueType: string; ValueData: """{app}\JakeFrost.exe"" ""%1"""
Root: HKCU; Subkey: "{#ClassesKey}\.fpgift\OpenWithProgids"; ValueType: string; ValueName: "{#GiftProgId}"; ValueData: ""; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "{#ClassesKey}\.fpgift"; ValueType: string; ValueData: "{#GiftProgId}"; Check: UnclaimedGiftExtension

[Run]
Filename: "{app}\JakeFrost.exe"; WorkingDir: "{app}"; Flags: nowait skipifsilent

[Code]
function InitializeSetup: Boolean;
var
  ResultCode: Integer;
begin
  Result := IsDotNetInstalled(net48, 0);
  if not Result then
    if SuppressibleMsgBox('Jake Frost needs Microsoft .NET Framework 4.8. Open the Microsoft download page? After installing it, run Jake Frost Setup again.',
      mbConfirmation, MB_YESNO, IDNO) = IDYES then
      ShellExec('open', 'https://dotnet.microsoft.com/en-us/download/dotnet-framework/net48', '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  InstalledText: String;
  InstalledVersion, NewVersion: Int64;
begin
  Result := '';
  if GetVersionNumbersString(ExpandConstant('{app}\JakeFrost.exe'), InstalledText) and
     StrToVersion(InstalledText, InstalledVersion) and StrToVersion('{#FileVersion}', NewVersion) then
    if ComparePackedVersion(InstalledVersion, NewVersion) > 0 then
      Result := 'A newer version of Jake Frost is already installed.';
end;

function UnclaimedGiftExtension: Boolean;
var
  Existing: String;
begin
  Result := not RegKeyExists(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.fpgift\UserChoice')
    and (not RegQueryStringValue(HKCR, '.fpgift', '', Existing) or (Existing = ''));
end;

procedure CurUninstallStepChanged(Step: TUninstallStep);
var
  Value: String;
begin
  if Step = usPostUninstall then begin
    if RegQueryStringValue(HKCU, '{#ClassesKey}\.fpgift', '', Value) and (Value = '{#GiftProgId}') then
      RegDeleteValue(HKCU, '{#ClassesKey}\.fpgift', '');
    RegDeleteKeyIfEmpty(HKCU, '{#ClassesKey}\.fpgift');
  end;
end;
