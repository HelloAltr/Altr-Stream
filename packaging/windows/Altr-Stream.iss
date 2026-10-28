; ==============================================================================
;  Altr Stream — Windows Native Manager Installer Configuration (Inno Setup 6)
;  Installs Altr Stream Manager.exe and registers Start Menu / Desktop shortcuts
; ==============================================================================

#ifndef MyAppVersion
  #define MyAppVersion "1.1.0"
#endif

#ifndef MyOutputDir
  #define MyOutputDir "..\..\dist"
#endif

[Setup]
AppId={{8B263B9B-89E2-4C95-B3DC-E7BDCF8D11A5}}
AppName=Altr Stream Manager
AppVersion={#MyAppVersion}
AppPublisher=HelloAltr
AppPublisherURL=https://helloaltr.com
AppSupportURL=https://github.com/helloaltr/altr-stream/issues
AppUpdatesURL=https://github.com/helloaltr/altr-stream/releases
DefaultDirName={autopf}\Altr Stream
DefaultGroupName=Altr Stream
DisableProgramGroupPage=yes
OutputDir={#MyOutputDir}
OutputBaseFilename=Altr Stream Installer
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=Altr Stream Manager
UninstallDisplayIcon={app}\Altr Stream Manager.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Manager Application and Shared Engine (Windows amd64)
Source: "build\altr-installer-engine.exe"; DestDir: "{app}"; DestName: "Altr Stream Manager.exe"; Flags: ignoreversion
Source: "build\altr-installer-engine.exe"; DestDir: "{app}"; DestName: "altr-installer-engine.exe"; Flags: ignoreversion
Source: "..\templates\INSTALLER_README.md"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Altr Stream\Altr Stream Manager"; Filename: "{app}\Altr Stream Manager.exe"
Name: "{autoprograms}\Altr Stream\Uninstall Altr Stream Manager"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Altr Stream Manager"; Filename: "{app}\Altr Stream Manager.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Altr Stream Manager.exe"; Description: "Launch Altr Stream Manager"; Flags: nowait postinstall skipifsilent

[Code]
// Protect user data and persistent Docker volumes during uninstallation
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    // Note: Node Docker containers and persistent data volumes ('altr_stream_data') are preserved.
  end;
end;
