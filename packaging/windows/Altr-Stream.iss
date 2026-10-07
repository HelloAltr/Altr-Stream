; ==============================================================================
;  Altr Stream — Windows Native Installer Configuration (Inno Setup 6)
;  Supported engine subcommands: detect-env, check-docker, launch-docker, wait-docker, conflict, install, repair, status, uninstall
; ==============================================================================

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0-beta"
#endif

#ifndef MyDockerImage
  ; Default development/E2E testing override: published 0.13.7-alpha image
  #define MyDockerImage "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"
#endif

#ifndef MyOutputDir
  #define MyOutputDir "..\..\dist"
#endif

[Setup]
AppId={{8B263B9B-89E2-4C95-B3DC-E7BDCF8D11A5}}
AppName=Altr Stream
AppVersion={#MyAppVersion}
AppPublisher=HelloAltr
AppPublisherURL=https://helloaltr.com
AppSupportURL=https://github.com/helloaltr/altr-stream/issues
AppUpdatesURL=https://github.com/helloaltr/altr-stream/releases
DefaultDirName={code:GetDefaultInstallDir}
UsePreviousAppDir=no
DisableDirPage=no
DisableProgramGroupPage=yes
OutputDir={#MyOutputDir}
OutputBaseFilename=Altr-Stream-Installer
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayName=Altr Stream
UninstallDisplayIcon={app}\altr-installer-engine.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; The compiled Go installer engine (Windows amd64)
Source: "build\altr-installer-engine.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\altr-installer-engine.exe"; DestDir: "{tmp}"; Flags: dontcopy
Source: "..\templates\INSTALLER_README.md"; DestDir: "{app}"; DestName: "README.txt"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\Altr Stream\Altr Stream Web UI"; Filename: "http://localhost:8000"
Name: "{userprograms}\Altr Stream\Altr Stream Status"; Filename: "{cmd}"; Parameters: "/k """"{app}\altr-installer-engine.exe"" status"""
Name: "{userprograms}\Altr Stream\Altr Stream Repair"; Filename: "{cmd}"; Parameters: "/k """"{app}\altr-installer-engine.exe"" repair --target-dir """"{app}"""""""
Name: "{userprograms}\Altr Stream\Uninstall Altr Stream"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\altr-installer-engine.exe"; Parameters: "launch-browser --url ""http://localhost:8000"""; Description: "Launch Altr Stream in web browser"; Flags: nowait postinstall skipifsilent; Check: IsInstallSuccessful

[Code]
var
  DockerStatusLabel: TLabel;
  DockerDetailLabel: TLabel;
  StartDockerBtn: TNewButton;
  RetryPrereqBtn: TNewButton;
  ViewPrereqDetailsBtn: TNewButton;
  ViewLogBtn: TNewButton;
  LastDockerDiagText: string;
  PrereqPage: TWizardPage;
  DockerReady: Boolean;
  InstallSucceeded: Boolean;
  InstallErrorMessage: string;
  RecoveryForm: TSetupForm;
  RecovHeadingLabel: TLabel;
  RecovMsgLabel: TLabel;
  RecovPathEdit: TNewEdit;
  RecovInstructLabel: TLabel;
  RecovOpenBtn: TNewButton;
  RecovRetryBtn: TNewButton;
  RecovDetailsBtn: TNewButton;
  RecovCancelBtn: TNewButton;
  CurrentSharePath: string;
  CurrentDiagText: string;
  UserRecoveryChoice: Integer;
  ShouldReplaceExisting: Boolean;

function IsInstallSuccessful: Boolean;
begin
  Result := InstallSucceeded;
end;

// Resolve clean Windows user home directory (matches Go os.UserHomeDir), avoiding redirected Documents/OneDrive
function GetDefaultInstallDir(Param: string): string;
var
  UserProfile: string;
begin
  UserProfile := GetEnv('USERPROFILE');
  if UserProfile = '' then
    UserProfile := GetEnv('HOME');
  if UserProfile = '' then
    UserProfile := ExpandConstant('{sysuserinfopath}');
  if UserProfile = '' then
    UserProfile := ExpandConstant('{localappdata}\..');
  Result := UserProfile + '\.altr-stream';
end;

type
  TMsg = record
    hwnd: HWND;
    message: UINT;
    wParam: Longint;
    lParam: Longint;
    time: DWORD;
    pt: TPoint;
  end;

function PeekMessage(var lpMsg: TMsg; hWnd: HWND; wMsgFilterMin, wMsgFilterMax, wRemoveMsg: UINT): BOOL;
  external 'PeekMessageW@user32.dll stdcall';
function TranslateMessage(const lpMsg: TMsg): BOOL;
  external 'TranslateMessage@user32.dll stdcall';
function DispatchMessage(const lpMsg: TMsg): Longint;
  external 'DispatchMessageW@user32.dll stdcall';
function FindWindow(lpClassName, lpWindowName: string): HWND;
  external 'FindWindowW@user32.dll stdcall';
function SetForegroundWindow(hWnd: HWND): BOOL;
  external 'SetForegroundWindow@user32.dll stdcall';
function ShowWindow(hWnd: HWND; nCmdShow: Integer): BOOL;
  external 'ShowWindow@user32.dll stdcall';
function GetTickCount: DWORD;
  external 'GetTickCount@kernel32.dll stdcall';

procedure BringDockerToFront;
var
  DockerHwnd: HWND;
begin
  DockerHwnd := FindWindow('', 'Docker Desktop');
  if DockerHwnd <> 0 then
  begin
    ShowWindow(DockerHwnd, 9); // SW_RESTORE
    SetForegroundWindow(DockerHwnd);
  end;
end;

procedure ProcessSystemMessages;
var
  Msg: TMsg;
begin
  while PeekMessage(Msg, 0, 0, 0, 1) do
  begin
    TranslateMessage(Msg);
    DispatchMessage(Msg);
  end;
end;

// Helper to execute engine and capture stdout text with active message pumping and bounded timeout
function RunEngineCapture(const EngineExe, Params: string; out OutputText: string): Integer;
var
  TempFile: string;
  DoneFile: string;
  CmdLine: string;
  ResultCode: Integer;
  RawOutput: AnsiString;
  RawDone: AnsiString;
  StartTick: DWORD;
  DoneCodeStr: string;
begin
  TempFile := ExpandConstant('{tmp}\engine_out.txt');
  DoneFile := ExpandConstant('{tmp}\engine_cmd_done.txt');
  DeleteFile(TempFile);
  DeleteFile(DoneFile);
  
  CmdLine := '/v:on /c ""' + EngineExe + '" ' + Params + ' > "' + TempFile + '" 2>&1 & echo !ERRORLEVEL! > "' + DoneFile + '""';
  if not Exec(ExpandConstant('{cmd}'), CmdLine, '', SW_HIDE, ewNoWait, ResultCode) then
  begin
    OutputText := 'Failed to execute installer engine process.';
    Result := -1;
    Exit;
  end;

  StartTick := GetTickCount;
  // Bounded timeout of 15 seconds with active message pumping to prevent UI thread lockup
  while (not FileExists(DoneFile)) and (GetTickCount - StartTick < 15000) do
  begin
    Sleep(25);
    ProcessSystemMessages;
  end;

  // Let file buffer flush
  Sleep(50);
  ProcessSystemMessages;

  ResultCode := 1;
  if FileExists(DoneFile) then
  begin
    if LoadStringFromFile(DoneFile, RawDone) then
    begin
      DoneCodeStr := Trim(String(RawDone));
      ResultCode := StrToIntDef(DoneCodeStr, 1);
    end;
    DeleteFile(DoneFile);
  end;

  if FileExists(TempFile) then
  begin
    LoadStringFromFile(TempFile, RawOutput);
    OutputText := String(RawOutput);
    DeleteFile(TempFile);
  end
  else
  begin
    if ResultCode <> 0 then
      OutputText := 'Installer engine command timed out or did not produce output.'
    else
      OutputText := '';
  end;

  Result := ResultCode;
end;

// Execute engine with real-time progress polling without freezing UI
function RunEngineWithProgress(const EngineExe, Params: string; out OutputText: string): Integer;
var
  CmdLine: string;
  ProgFile: string;
  DoneFile: string;
  CmdDoneFile: string;
  OutFile: string;
  RawOutput: AnsiString;
  RawProg: AnsiString;
  RawDone: AnsiString;
  ProgLine: string;
  FullOutput: string;
  CurPercent: Integer;
  StageText: string;
  MsgText: string;
  SepPos1, SepPos2, SepPos3, SepPos4: Integer;
  ErrIdx: Integer;
  ResultCode: Integer;
  DoneCodeStr: string;
begin
  ProgFile := ExpandConstant('{tmp}\install_progress.txt');
  DoneFile := ExpandConstant('{tmp}\install_done.txt');
  CmdDoneFile := ExpandConstant('{tmp}\install_cmd_done.txt');
  OutFile := ExpandConstant('{tmp}\install_out.txt');

  DeleteFile(ProgFile);
  DeleteFile(DoneFile);
  DeleteFile(CmdDoneFile);
  DeleteFile(OutFile);

  OutputText := '';

  CmdLine := '/v:on /c ""' + EngineExe + '" ' + Params + ' --progress-file "' + ProgFile + '" --done-file "' + DoneFile + '" > "' + OutFile + '" 2>&1 & echo !ERRORLEVEL! > "' + CmdDoneFile + '""';

  WizardForm.ProgressGauge.Position := 0;
  WizardForm.ProgressGauge.Visible := True;
  WizardForm.CancelButton.Enabled := False;

  if not Exec(ExpandConstant('{cmd}'), CmdLine, '', SW_HIDE, ewNoWait, ResultCode) then
  begin
    OutputText := 'Failed to launch installer engine process.';
    Result := -1;
    Exit;
  end;

  while (not FileExists(DoneFile)) and (not FileExists(CmdDoneFile)) do
  begin
    Sleep(100);
    ProcessSystemMessages;
    WizardForm.Refresh;

    if FileExists(ProgFile) then
    begin
      if LoadStringFromFile(ProgFile, RawProg) then
      begin
        ProgLine := Trim(String(RawProg));
        // Expected format: <percent>|<stage_idx>|<total_stages>|<stage>|<message>
        SepPos1 := Pos('|', ProgLine);
        if SepPos1 > 0 then
        begin
          CurPercent := StrToIntDef(Copy(ProgLine, 1, SepPos1 - 1), -1);
          Delete(ProgLine, 1, SepPos1);

          SepPos2 := Pos('|', ProgLine);
          if SepPos2 > 0 then
            Delete(ProgLine, 1, SepPos2);

          SepPos3 := Pos('|', ProgLine);
          if SepPos3 > 0 then
            Delete(ProgLine, 1, SepPos3);

          SepPos4 := Pos('|', ProgLine);
          if SepPos4 > 0 then
          begin
            StageText := Copy(ProgLine, 1, SepPos4 - 1);
            MsgText := Copy(ProgLine, SepPos4 + 1, Length(ProgLine));
          end
          else
          begin
            StageText := ProgLine;
            MsgText := '';
          end;

          if CurPercent >= 0 then
            WizardForm.ProgressGauge.Position := CurPercent;

          if MsgText <> '' then
            WizardForm.StatusLabel.Caption := StageText + ': ' + MsgText
          else if StageText <> '' then
            WizardForm.StatusLabel.Caption := StageText;
        end;
      end;
    end;
  end;

  // Let file buffers flush
  Sleep(150);
  ProcessSystemMessages;

  // Default to failure: genuine success requires ALL checks to pass
  ResultCode := 1;

  // Check 1: Engine-generated DoneFile
  if FileExists(DoneFile) then
  begin
    if LoadStringFromFile(DoneFile, RawDone) then
    begin
      DoneCodeStr := Trim(String(RawDone));
      if Pos('0|', DoneCodeStr) = 1 then
      begin
        ResultCode := 0;
        OutputText := 'Success';
      end
      else
      begin
        if Pos('2|', DoneCodeStr) = 1 then
          ResultCode := 2
        else
          ResultCode := 1;
        OutputText := Trim(Copy(DoneCodeStr, 3, Length(DoneCodeStr)));
      end;
    end;
    DeleteFile(DoneFile);
  end;

  // Check 2: CMD !ERRORLEVEL! exit code
  if FileExists(CmdDoneFile) then
  begin
    if LoadStringFromFile(CmdDoneFile, RawDone) then
    begin
      DoneCodeStr := Trim(String(RawDone));
      if DoneCodeStr = '2' then
      begin
        if ResultCode <> 0 then
          ResultCode := 2;
      end
      else if DoneCodeStr <> '0' then
      begin
        if ResultCode <> 2 then
          ResultCode := 1;
      end;
    end;
    DeleteFile(CmdDoneFile);
  end;

  // Check 3: ProgFile must confirm completion, never failure
  if FileExists(ProgFile) then
  begin
    if LoadStringFromFile(ProgFile, RawProg) then
    begin
      ProgLine := Trim(String(RawProg));
      if (Pos('-1|', ProgLine) = 1) or (Pos('|Failed|', ProgLine) > 0) or (Pos('|FileSharingRequired|', ProgLine) > 0) then
      begin
        if Pos('|FileSharingRequired|', ProgLine) > 0 then
          ResultCode := 2
        else if ResultCode <> 2 then
          ResultCode := 1;

        if OutputText = '' then
        begin
          SepPos4 := Pos('|FileSharingRequired|', ProgLine);
          if SepPos4 > 0 then
            OutputText := Trim(Copy(ProgLine, SepPos4 + Length('|FileSharingRequired|'), Length(ProgLine)))
          else
          begin
            SepPos4 := Pos('|Failed|', ProgLine);
            if SepPos4 > 0 then
              OutputText := Trim(Copy(ProgLine, SepPos4 + Length('|Failed|'), Length(ProgLine)));
          end;
        end;
      end;
      if (Pos('100|', ProgLine) <> 1) and (Pos('|Done|', ProgLine) = 0) and (ResultCode = 0) then
        ResultCode := 1;
    end;
    DeleteFile(ProgFile);
  end
  else
  begin
    if ResultCode = 0 then
      ResultCode := 1;
  end;

  // Check 4: OutFile capture and error validation
  if FileExists(OutFile) then
  begin
    LoadStringFromFile(OutFile, RawOutput);
    FullOutput := Trim(String(RawOutput));
    DeleteFile(OutFile);
    if (Pos('Installation failed:', FullOutput) > 0) or
       (Pos('Repair failed:', FullOutput) > 0) then
    begin
      if (Pos('FILE_SHARING_REQUIRED', FullOutput) > 0) or (ResultCode = 2) then
        ResultCode := 2
      else
        ResultCode := 1;

      if OutputText = '' then
      begin
        ErrIdx := Pos('Installation failed:', FullOutput);
        if ErrIdx > 0 then
          OutputText := Trim(Copy(FullOutput, ErrIdx + Length('Installation failed:'), Length(FullOutput)))
        else
        begin
          ErrIdx := Pos('Repair failed:', FullOutput);
          if ErrIdx > 0 then
            OutputText := Trim(Copy(FullOutput, ErrIdx + Length('Repair failed:'), Length(FullOutput)))
          else
            OutputText := FullOutput;
        end;
      end;
    end;
  end;

  if Pos('FILE_SHARING_REQUIRED', OutputText) > 0 then
    ResultCode := 2;

  if (ResultCode <> 0) and (OutputText = '') then
    OutputText := 'Container setup failed during runtime initialization.';

  Result := ResultCode;

end;

// Handle command-line flags like /REPAIR or /STATUS before showing wizard
function InitializeSetup(): Boolean;
var
  I: Integer;
  P: string;
  EngineTmp: string;
  OutputStr: string;
  TargetAppDir: string;
begin
  Result := True;
  for I := 1 to ParamCount do
  begin
    P := Uppercase(ParamStr(I));
    if (P = '/REPAIR') or (P = '-REPAIR') or (P = '--REPAIR') then
    begin
      ExtractTemporaryFile('altr-installer-engine.exe');
      EngineTmp := ExpandConstant('{tmp}\altr-installer-engine.exe');
      TargetAppDir := GetDefaultInstallDir('');
      RunEngineCapture(EngineTmp, 'repair --target-dir "' + TargetAppDir + '"', OutputStr);
      MsgBox('Altr Stream Repair Result:' + #13#10#13#10 + OutputStr, mbInformation, MB_OK);
      Result := False;
      Exit;
    end
    else if (P = '/STATUS') or (P = '-STATUS') or (P = '--STATUS') then
    begin
      ExtractTemporaryFile('altr-installer-engine.exe');
      EngineTmp := ExpandConstant('{tmp}\altr-installer-engine.exe');
      RunEngineCapture(EngineTmp, 'status', OutputStr);
      MsgBox('Altr Stream Status:' + #13#10#13#10 + OutputStr, mbInformation, MB_OK);
      Result := False;
      Exit;
    end;
  end;
end;

procedure ViewPrereqDetailsBtnClick(Sender: TObject);
begin
  if LastDockerDiagText = '' then
    MsgBox('No technical diagnostic information is available.', mbInformation, MB_OK)
  else
    MsgBox('Technical Diagnostic Details:' + #13#10#13#10 + LastDockerDiagText, mbInformation, MB_OK);
end;

procedure ViewLogBtnClick(Sender: TObject);
var
  LogPath: string;
  ResCode: Integer;
begin
  LogPath := ExpandConstant('{app}\.docker_start.log');
  if not FileExists(LogPath) then
    LogPath := ExpandConstant('{tmp}\install_out.txt');

  if FileExists(LogPath) then
  begin
    Exec(ExpandConstant('{cmd}'), '/c start notepad.exe "' + LogPath + '"', '', SW_HIDE, ewNoWait, ResCode);
  end
  else
  begin
    MsgBox('Log file not found at:' + #13#10 + LogPath, mbInformation, MB_OK);
  end;
end;

procedure CheckPrerequisitesAndUpdateUI; forward;

procedure StartDockerBtnClick(Sender: TObject);
var
  EngineTmp: string;
  OutputStr: string;
  ResCode: Integer;
  StartTick: DWORD;
  ElapsedSec: Integer;
  MaxWaitMs: DWORD;
  DockerBecameReady: Boolean;
  I: Integer;
begin
  ExtractTemporaryFile('altr-installer-engine.exe');
  EngineTmp := ExpandConstant('{tmp}\altr-installer-engine.exe');
  StartDockerBtn.Enabled := False;
  RetryPrereqBtn.Enabled := False;
  ViewPrereqDetailsBtn.Visible := False;

  DockerStatusLabel.Font.Color := $001890FF; // Orange
  DockerStatusLabel.Caption := 'Starting Docker Desktop...';
  DockerDetailLabel.Caption :=
    'Launching Docker Desktop application...' + #13#10#13#10 +
    'Please wait while the Docker background service starts.';
  ProcessSystemMessages;
  WizardForm.Refresh;

  // 1. Dispatch detached Docker Desktop launch (returns immediately)
  ResCode := RunEngineCapture(EngineTmp, 'launch-docker', OutputStr);

  // 2. Poll for Docker Engine readiness with responsive message pumping
  StartTick := GetTickCount;
  MaxWaitMs := 75000; // 75-second hard bounded timeout for Docker startup
  DockerBecameReady := False;

  while (GetTickCount - StartTick < MaxWaitMs) and (not DockerBecameReady) do
  begin
    ElapsedSec := (GetTickCount - StartTick) div 1000;
    DockerStatusLabel.Caption := 'Starting Docker Desktop... (' + IntToStr(ElapsedSec) + 's)';
    DockerDetailLabel.Caption :=
      'Waiting for Docker Engine daemon to respond (' + IntToStr(ElapsedSec) + 's elapsed)...' + #13#10#13#10 +
      'Docker Desktop is initializing background services.' + #13#10 +
      'Setup will automatically continue as soon as Docker is ready.';
    ProcessSystemMessages;
    WizardForm.Refresh;

    // Run short probe check-docker (takes ~100ms when ready, up to ~2s when offline)
    ResCode := RunEngineCapture(EngineTmp, 'check-docker', OutputStr);
    LastDockerDiagText := Trim(OutputStr);

    if Pos('"state": "ready"', OutputStr) > 0 then
    begin
      DockerBecameReady := True;
      Break;
    end;

    // Sleep 1 second in 100ms intervals pumping messages to keep the window 100% responsive
    for I := 1 to 10 do
    begin
      Sleep(100);
      ProcessSystemMessages;
    end;
  end;

  StartDockerBtn.Enabled := True;
  RetryPrereqBtn.Enabled := True;

  CheckPrerequisitesAndUpdateUI;
end;

procedure RetryPrereqBtnClick(Sender: TObject);
begin
  DockerStatusLabel.Caption := 'Checking Docker prerequisites...';
  DockerDetailLabel.Caption := 'Probing Docker CLI, Docker Desktop, and Docker daemon readiness...';
  ProcessSystemMessages;
  WizardForm.Refresh;
  CheckPrerequisitesAndUpdateUI;
end;

procedure CheckPrerequisitesAndUpdateUI;
var
  EngineTmp: string;
  OutputStr: string;
  ResCode: Integer;
begin
  ExtractTemporaryFile('altr-installer-engine.exe');
  EngineTmp := ExpandConstant('{tmp}\altr-installer-engine.exe');

  ResCode := RunEngineCapture(EngineTmp, 'check-docker', OutputStr);
  LastDockerDiagText := Trim(OutputStr);

  if Pos('"state": "ready"', OutputStr) > 0 then
  begin
    DockerReady := True;
    DockerStatusLabel.Font.Color := clGreen;
    DockerStatusLabel.Caption := 'Docker Engine: Ready';
    DockerDetailLabel.Caption :=
      'Docker Engine and Docker Compose are running and ready.' + #13#10#13#10 +
      'Click "Next" to choose your installation directory and proceed.';
    StartDockerBtn.Visible := False;
    RetryPrereqBtn.Visible := True;
    ViewPrereqDetailsBtn.Visible := False;
    WizardForm.NextButton.Enabled := True;
  end
  else if (Pos('"state": "stopped"', OutputStr) > 0) or
          (Pos('"engine_running": false', OutputStr) > 0) or
          (Pos('Engine Offline', OutputStr) > 0) or
          (Pos('Docker Desktop is Stopped', OutputStr) > 0) then
  begin
    DockerReady := False;
    DockerStatusLabel.Font.Color := $001890FF; // Orange
    DockerStatusLabel.Caption := 'Docker Desktop is Stopped';
    DockerDetailLabel.Caption :=
      'Docker is installed, but the Docker Engine is currently offline.' + #13#10#13#10 +
      'Click "Start Docker Desktop" below to start Docker automatically, or start Docker Desktop manually and click "Retry Check".' + #13#10#13#10 +
      'Wait for Docker Desktop to finish starting before continuing.';
    StartDockerBtn.Visible := True;
    RetryPrereqBtn.Visible := True;
    ViewPrereqDetailsBtn.Visible := True;
  end
  else if Pos('"state": "not_installed"', OutputStr) > 0 then
  begin
    DockerReady := False;
    DockerStatusLabel.Font.Color := clRed;
    DockerStatusLabel.Caption := 'Docker Desktop is Not Installed';
    DockerDetailLabel.Caption :=
      'Altr Stream requires Docker Desktop to operate.' + #13#10#13#10 +
      'Please install Docker Desktop from:' + #13#10 +
      'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe' + #13#10#13#10 +
      'After installing, start Docker Desktop and click "Retry Check".';
    StartDockerBtn.Visible := False;
    RetryPrereqBtn.Visible := True;
    ViewPrereqDetailsBtn.Visible := True;
  end
  else
  begin
    DockerReady := False;
    DockerStatusLabel.Font.Color := clRed;
    DockerStatusLabel.Caption := 'Docker Status: Attention Required';
    DockerDetailLabel.Caption :=
      'Docker was detected, but Altr Stream was unable to connect to the Docker Engine.' + #13#10#13#10 +
      'Please verify that Docker Desktop is running and fully initialized.' + #13#10#13#10 +
      'Click "Start Docker Desktop" to start it, or "Technical Details..." to view diagnostic info.';
    StartDockerBtn.Visible := True;
    RetryPrereqBtn.Visible := True;
    ViewPrereqDetailsBtn.Visible := True;
  end;

  ProcessSystemMessages;
  WizardForm.Refresh;
end;

// Initialize custom wizard UI for Docker prerequisites
procedure InitializeWizard;
begin
  DockerReady := False;
  InstallSucceeded := False;
  InstallErrorMessage := '';
  LastDockerDiagText := '';

  // Create custom prerequisite status page right after Welcome page
  PrereqPage := CreateCustomPage(wpWelcome,
    'System Prerequisites Check',
    'Verifying Docker Engine and Docker Compose availability.');

  DockerStatusLabel := TLabel.Create(WizardForm);
  DockerStatusLabel.Parent := PrereqPage.Surface;
  DockerStatusLabel.Left := ScaleX(8);
  DockerStatusLabel.Top := ScaleY(12);
  DockerStatusLabel.Width := PrereqPage.SurfaceWidth - ScaleX(16);
  DockerStatusLabel.Height := ScaleY(30);
  DockerStatusLabel.AutoSize := False;
  DockerStatusLabel.Font.Size := 11;
  DockerStatusLabel.Font.Style := [fsBold];
  DockerStatusLabel.Caption := 'Checking Docker prerequisites...';

  DockerDetailLabel := TLabel.Create(WizardForm);
  DockerDetailLabel.Parent := PrereqPage.Surface;
  DockerDetailLabel.Left := ScaleX(8);
  DockerDetailLabel.Top := ScaleY(48);
  DockerDetailLabel.Width := PrereqPage.SurfaceWidth - ScaleX(16);
  DockerDetailLabel.Height := ScaleY(120);
  DockerDetailLabel.AutoSize := False;
  DockerDetailLabel.WordWrap := True;
  DockerDetailLabel.Caption := 'Probing Docker CLI, Docker Desktop, and Docker daemon readiness...';

  StartDockerBtn := TNewButton.Create(WizardForm);
  StartDockerBtn.Parent := PrereqPage.Surface;
  StartDockerBtn.Left := ScaleX(8);
  StartDockerBtn.Top := ScaleY(180);
  StartDockerBtn.Width := ScaleX(145);
  StartDockerBtn.Height := ScaleY(26);
  StartDockerBtn.Caption := 'Start Docker Desktop';
  StartDockerBtn.OnClick := @StartDockerBtnClick;
  StartDockerBtn.Visible := False;

  RetryPrereqBtn := TNewButton.Create(WizardForm);
  RetryPrereqBtn.Parent := PrereqPage.Surface;
  RetryPrereqBtn.Left := ScaleX(160);
  RetryPrereqBtn.Top := ScaleY(180);
  RetryPrereqBtn.Width := ScaleX(100);
  RetryPrereqBtn.Height := ScaleY(26);
  RetryPrereqBtn.Caption := 'Retry Check';
  RetryPrereqBtn.OnClick := @RetryPrereqBtnClick;
  RetryPrereqBtn.Visible := False;

  ViewPrereqDetailsBtn := TNewButton.Create(WizardForm);
  ViewPrereqDetailsBtn.Parent := PrereqPage.Surface;
  ViewPrereqDetailsBtn.Left := ScaleX(268);
  ViewPrereqDetailsBtn.Top := ScaleY(180);
  ViewPrereqDetailsBtn.Width := ScaleX(135);
  ViewPrereqDetailsBtn.Height := ScaleY(26);
  ViewPrereqDetailsBtn.Caption := 'Technical Details...';
  ViewPrereqDetailsBtn.OnClick := @ViewPrereqDetailsBtnClick;
  ViewPrereqDetailsBtn.Visible := False;

  ViewLogBtn := TNewButton.Create(WizardForm);
  ViewLogBtn.Parent := WizardForm.FinishedPage;
  ViewLogBtn.Left := WizardForm.FinishedLabel.Left;
  ViewLogBtn.Top := WizardForm.FinishedLabel.Top + ScaleY(228);
  ViewLogBtn.Width := ScaleX(160);
  ViewLogBtn.Height := ScaleY(26);
  ViewLogBtn.Caption := 'View Installation Log';
  ViewLogBtn.OnClick := @ViewLogBtnClick;
  ViewLogBtn.Visible := False;

  // Explicitly initialize directory edit to clean user profile
  WizardForm.DirEdit.Text := GetDefaultInstallDir('');
end;

// Update Docker status on prerequisite page and configure Finished page
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpSelectDir then
  begin
    // Guarantee that directory selection never pre-populates with OneDrive
    if (Pos('\ONEDRIVE\', Uppercase(WizardForm.DirEdit.Text)) > 0) or
       (Pos('/ONEDRIVE/', Uppercase(WizardForm.DirEdit.Text)) > 0) then
    begin
      WizardForm.DirEdit.Text := GetDefaultInstallDir('');
    end;
  end
  else if CurPageID = PrereqPage.ID then
  begin
    WizardForm.ProgressGauge.Visible := False;
    CheckPrerequisitesAndUpdateUI;
  end
  else if CurPageID = wpFinished then
  begin
    if not InstallSucceeded then
    begin
      WizardForm.FinishedHeadingLabel.Caption := 'Altr Stream Setup Incomplete';
      WizardForm.FinishedHeadingLabel.Height := ScaleY(48);
      WizardForm.FinishedLabel.Top := WizardForm.FinishedHeadingLabel.Top + WizardForm.FinishedHeadingLabel.Height + ScaleY(8);
      WizardForm.FinishedLabel.Height := ScaleY(220);
      WizardForm.FinishedLabel.Caption :=
        'Installation could not be completed.' + #13#10#13#10 +
        InstallErrorMessage + #13#10#13#10 +
        'Diagnostic logs are available at:' + #13#10 +
        '  ' + ExpandConstant('{app}\.docker_start.log') + #13#10#13#10 +
        'Click "View Installation Log" below to inspect container logs,' + #13#10 +
        'or launch "Altr Stream Repair" from the Start Menu after resolving the issue.';
      WizardForm.RunList.Visible := False; // Hide browser launch checkbox completely
      ViewLogBtn.Visible := True;
    end
    else
    begin
      WizardForm.FinishedHeadingLabel.Caption := 'Completing the Altr Stream Setup Wizard';
      WizardForm.FinishedLabel.Caption :=
        'Setup has finished installing Altr Stream on your computer.' + #13#10#13#10 +
        'The application container is running and healthy on port 8000.' + #13#10#13#10 +
        'Click Finish to exit Setup.';
      WizardForm.RunList.Visible := True;
      ViewLogBtn.Visible := False;
    end;
  end;
end;

// Handle Next button click on custom prerequisite page and directory validation
function NextButtonClick(CurPageID: Integer): Boolean;
var
  EngineTmp: string;
  OutputStr: string;
  ResCode: Integer;
  SelectedDir: string;
begin
  Result := True;

  if CurPageID = wpSelectDir then
  begin
    SelectedDir := WizardDirValue;
    if (Pos('\ONEDRIVE\', Uppercase(SelectedDir)) > 0) or (Pos('/ONEDRIVE/', Uppercase(SelectedDir)) > 0) then
    begin
      if MsgBox('Notice: The selected installation folder is inside OneDrive:' + #13#10 +
                '  ' + SelectedDir + #13#10#13#10 +
                'OneDrive synchronization can conflict with Docker database locks and container volume mounts.' + #13#10#13#10 +
                'We strongly recommend installing to your standard profile directory instead:' + #13#10 +
                '  ' + GetDefaultInstallDir('') + #13#10#13#10 +
                'Do you wish to continue installing to OneDrive anyway?',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) <> IDYES then
      begin
        WizardForm.DirEdit.Text := GetDefaultInstallDir('');
        Result := False;
        Exit;
      end;
    end;
  end
  else if CurPageID = PrereqPage.ID then
  begin
    EngineTmp := ExpandConstant('{tmp}\altr-installer-engine.exe');
    
    // Strictly require Docker to be ready before proceeding
    if not DockerReady then
    begin
      ResCode := RunEngineCapture(EngineTmp, 'check-docker', OutputStr);
      LastDockerDiagText := Trim(OutputStr);
      
      if Pos('"state": "ready"', OutputStr) > 0 then
      begin
        DockerReady := True;
        Result := True;
        Exit;
      end
      else if Pos('"state": "not_installed"', OutputStr) > 0 then
      begin
        if MsgBox('Docker Desktop is required to run Altr Stream.' + #13#10#13#10 +
                  'Would you like to open the official Docker Desktop download page in your browser now?',
                  mbConfirmation, MB_YESNO) = IDYES then
        begin
          Exec(ExpandConstant('{cmd}'),
            '/c start "" "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"',
            '', SW_HIDE, ewNoWait, ResCode);
        end;
        Result := False; // Strictly hold on prerequisite page until installed
        Exit;
      end
      else if (Pos('"state": "stopped"', OutputStr) > 0) or
              (Pos('"engine_running": false', OutputStr) > 0) or
              (Pos('Engine Offline', OutputStr) > 0) then
      begin
        // Automatically attempt to start Docker Desktop
        StartDockerBtnClick(nil);
        if DockerReady then
        begin
          Result := True;
          Exit;
        end
        else
        begin
          MsgBox('Docker Engine is currently offline.' + #13#10#13#10 +
                 'Altr Stream cannot continue until Docker Desktop is running.' + #13#10#13#10 +
                 'Please start Docker Desktop, wait for it to finish starting, and click "Retry Check".',
                 mbError, MB_OK);
          Result := False;
          Exit;
        end;
      end
      else
      begin
        MsgBox('Docker Engine must be running before installation can continue.' + #13#10#13#10 +
               'Please verify Docker Desktop is running and click "Retry Check".',
               mbError, MB_OK);
        Result := False;
        Exit;
      end;
    end;
  end
  else if CurPageID = wpReady then
  begin
    // Check for container conflict before starting installation
    ExtractTemporaryFile('altr-installer-engine.exe');
    EngineTmp := ExpandConstant('{tmp}\altr-installer-engine.exe');
    ResCode := RunEngineCapture(EngineTmp, 'conflict', OutputStr);
    
    if Pos('"exists": true', OutputStr) > 0 then
    begin
      if (Pos('"conflict_type": "port_docker"', OutputStr) > 0) or
         (Pos('"conflict_type": "port_process"', OutputStr) > 0) then
      begin
        MsgBox('Port conflict detected:' + #13#10#13#10 +
               'Required host port 8000 is already in use by another container or application.' + #13#10#13#10 +
               'Please stop the conflicting service and restart the installer.',
               mbError, MB_OK);
        Result := False;
        Exit;
      end;

      ShouldReplaceExisting := True;
      if Pos('"is_altr_stream": true', OutputStr) > 0 then
      begin
        if MsgBox('An existing Altr Stream container was detected in Docker.' + #13#10 + #13#10 +
                  'Installation will safely replace this container and preserve your persistent application data and settings.' + #13#10 + #13#10 +
                  'Do you want to proceed with replacing the container?',
                  mbConfirmation, MB_YESNO) <> IDYES then
        begin
          Result := False;
          Exit;
        end;
      end
      else
      begin
        if MsgBox('An existing container named "altr-stream" from an external or older image was detected in Docker.' + #13#10 + #13#10 +
                  'Continuing will remove this container while preserving all existing data volumes.' + #13#10 + #13#10 +
                  'Do you want to proceed with replacing the container?',
                  mbConfirmation, MB_YESNO) <> IDYES then
        begin
          Result := False;
          Exit;
        end;
      end;
    end
    else
    begin
      ShouldReplaceExisting := False;
    end;
  end;
end;

const
  CHOICE_RETRY = 1;
  CHOICE_CANCEL = 2;

function IsFileSharingRequired(const OutputStr: string; var TargetPath: string): Boolean;
var
  Idx, SepPos2: Integer;
  SubStr: string;
begin
  Result := False;
  TargetPath := '';
  Idx := Pos('FILE_SHARING_REQUIRED|', OutputStr);
  if Idx > 0 then
  begin
    Result := True;
    SubStr := Copy(OutputStr, Idx + Length('FILE_SHARING_REQUIRED|'), Length(OutputStr));
    SepPos2 := Pos('|', SubStr);
    if SepPos2 > 0 then
      TargetPath := Copy(SubStr, 1, SepPos2 - 1)
    else
      TargetPath := SubStr;
  end
  else if (Pos('is not shared from the host', Lowercase(OutputStr)) > 0) or
          (Pos('file sharing', Lowercase(OutputStr)) > 0) or
          (Pos('filesharing', Lowercase(OutputStr)) > 0) then
  begin
    Result := True;
    TargetPath := ExpandConstant('{app}\data\updates');
  end;
end;

procedure RecovOpenBtnClick(Sender: TObject);
var
  ResCode: Integer;
  EngineTmp: string;
  OutputStr: string;
  DesktopExe: string;
  Attempt: Integer;
begin
  ExtractTemporaryFile('altr-installer-engine.exe');
  EngineTmp := ExpandConstant('{tmp}\altr-installer-engine.exe');

  // Attempt 1: Call Go engine helper to launch / focus Docker Desktop
  RunEngineCapture(EngineTmp, 'open-docker-settings', OutputStr);

  // Attempt 2: Direct executable fallback in standard Program Files / AppData locations
  DesktopExe := GetEnv('ProgramFiles') + '\Docker\Docker\Docker Desktop.exe';
  if not FileExists(DesktopExe) then
    DesktopExe := GetEnv('ProgramW6432') + '\Docker\Docker\Docker Desktop.exe';
  if not FileExists(DesktopExe) then
    DesktopExe := ExpandConstant('{localappdata}\Programs\Docker\Docker\Docker Desktop.exe');

  if FileExists(DesktopExe) then
    Exec(ExpandConstant('{cmd}'), '/c start "" "' + DesktopExe + '"', '', SW_HIDE, ewNoWait, ResCode);

  // Bring Docker Desktop window to foreground
  for Attempt := 1 to 5 do
  begin
    ProcessSystemMessages;
    BringDockerToFront;
    Sleep(200);
  end;

  MsgBox('Docker Desktop is opening.' + #13#10#13#10 +
         'To enable file sharing:' + #13#10 +
         '1. In Docker Desktop, go to Settings (gear icon) > Resources > File Sharing' + #13#10 +
         '2. Click "+" and add the folder:' + #13#10 +
         '   ' + CurrentSharePath + #13#10 +
         '3. Click "Apply & restart" in Docker Desktop' + #13#10#13#10 +
         'Once Docker Desktop restarts, click "Retry" in the setup window.',
         mbInformation, MB_OK);
end;

procedure RecovDetailsBtnClick(Sender: TObject);
var
  LogPath: string;
  ResCode: Integer;
begin
  LogPath := ExpandConstant('{app}\.docker_start.log');
  if not FileExists(LogPath) then
    LogPath := ExpandConstant('{tmp}\install_out.txt');

  if FileExists(LogPath) then
    Exec(ExpandConstant('{cmd}'), '/c start notepad.exe "' + LogPath + '"', '', SW_HIDE, ewNoWait, ResCode)
  else
    MsgBox('Technical Diagnostic Details:' + #13#10#13#10 + CurrentDiagText, mbInformation, MB_OK);
end;

procedure RecovRetryBtnClick(Sender: TObject);
begin
  UserRecoveryChoice := CHOICE_RETRY;
  RecoveryForm.Close;
end;

procedure RecovCancelBtnClick(Sender: TObject);
begin
  UserRecoveryChoice := CHOICE_CANCEL;
  RecoveryForm.Close;
end;

function ShowFileSharingRecoveryDialog(const TargetPath, DiagText: string): Integer;
begin
  CurrentSharePath := TargetPath;
  CurrentDiagText := DiagText;

  RecoveryForm := CreateCustomForm(ScaleX(520), ScaleY(340), False, False);
  try
    RecoveryForm.ClientWidth := ScaleX(520);
    RecoveryForm.ClientHeight := ScaleY(320);
    RecoveryForm.FlipAndCenterIfNeeded(True, WizardForm, False);
    RecoveryForm.Caption := 'Docker Desktop File Sharing Required';

    RecovHeadingLabel := TLabel.Create(RecoveryForm);
    RecovHeadingLabel.Parent := RecoveryForm;
    RecovHeadingLabel.Left := ScaleX(16);
    RecovHeadingLabel.Top := ScaleY(14);
    RecovHeadingLabel.Width := RecoveryForm.ClientWidth - ScaleX(32);
    RecovHeadingLabel.Height := ScaleY(24);
    RecovHeadingLabel.AutoSize := False;
    RecovHeadingLabel.Font.Size := 10;
    RecovHeadingLabel.Font.Style := [fsBold];
    RecovHeadingLabel.Caption := 'Docker Desktop requires permission to access Altr Stream data';

    RecovMsgLabel := TLabel.Create(RecoveryForm);
    RecovMsgLabel.Parent := RecoveryForm;
    RecovMsgLabel.Left := ScaleX(16);
    RecovMsgLabel.Top := ScaleY(42);
    RecovMsgLabel.Width := RecoveryForm.ClientWidth - ScaleX(32);
    RecovMsgLabel.Height := ScaleY(36);
    RecovMsgLabel.AutoSize := False;
    RecovMsgLabel.WordWrap := True;
    RecovMsgLabel.Caption :=
      'Docker cannot mount the required host directory because it is not shared in Docker Desktop''s host resources:';

    RecovPathEdit := TNewEdit.Create(RecoveryForm);
    RecovPathEdit.Parent := RecoveryForm;
    RecovPathEdit.Left := ScaleX(16);
    RecovPathEdit.Top := ScaleY(82);
    RecovPathEdit.Width := RecoveryForm.ClientWidth - ScaleX(32);
    RecovPathEdit.Height := ScaleY(24);
    RecovPathEdit.ReadOnly := True;
    RecovPathEdit.Text := CurrentSharePath;

    RecovInstructLabel := TLabel.Create(RecoveryForm);
    RecovInstructLabel.Parent := RecoveryForm;
    RecovInstructLabel.Left := ScaleX(16);
    RecovInstructLabel.Top := ScaleY(116);
    RecovInstructLabel.Width := RecoveryForm.ClientWidth - ScaleX(32);
    RecovInstructLabel.Height := ScaleY(140);
    RecovInstructLabel.AutoSize := False;
    RecovInstructLabel.WordWrap := True;
    RecovInstructLabel.Caption :=
      'To grant permission:' + #13#10 +
      '1. Click "Open Docker Settings" below' + #13#10 +
      '2. In Docker Desktop, navigate to Resources > File Sharing' + #13#10 +
      '3. Add the folder path shown above (or your user profile folder)' + #13#10 +
      '4. Click "Apply & restart" in Docker Desktop' + #13#10 +
      '5. Click "Retry" below to resume installation';

    RecovOpenBtn := TNewButton.Create(RecoveryForm);
    RecovOpenBtn.Parent := RecoveryForm;
    RecovOpenBtn.Left := ScaleX(16);
    RecovOpenBtn.Top := ScaleY(268);
    RecovOpenBtn.Width := ScaleX(170);
    RecovOpenBtn.Height := ScaleY(28);
    RecovOpenBtn.Caption := 'Open Docker Settings';
    RecovOpenBtn.OnClick := @RecovOpenBtnClick;

    RecovRetryBtn := TNewButton.Create(RecoveryForm);
    RecovRetryBtn.Parent := RecoveryForm;
    RecovRetryBtn.Left := ScaleX(194);
    RecovRetryBtn.Top := ScaleY(268);
    RecovRetryBtn.Width := ScaleX(90);
    RecovRetryBtn.Height := ScaleY(28);
    RecovRetryBtn.Caption := 'Retry';
    RecovRetryBtn.Default := True;
    RecovRetryBtn.OnClick := @RecovRetryBtnClick;

    RecovDetailsBtn := TNewButton.Create(RecoveryForm);
    RecovDetailsBtn.Parent := RecoveryForm;
    RecovDetailsBtn.Left := ScaleX(292);
    RecovDetailsBtn.Top := ScaleY(268);
    RecovDetailsBtn.Width := ScaleX(125);
    RecovDetailsBtn.Height := ScaleY(28);
    RecovDetailsBtn.Caption := 'Technical Details';
    RecovDetailsBtn.OnClick := @RecovDetailsBtnClick;

    RecovCancelBtn := TNewButton.Create(RecoveryForm);
    RecovCancelBtn.Parent := RecoveryForm;
    RecovCancelBtn.Left := ScaleX(425);
    RecovCancelBtn.Top := ScaleY(268);
    RecovCancelBtn.Width := ScaleX(79);
    RecovCancelBtn.Height := ScaleY(28);
    RecovCancelBtn.Caption := 'Cancel';
    RecovCancelBtn.Cancel := True;
    RecovCancelBtn.OnClick := @RecovCancelBtnClick;

    UserRecoveryChoice := CHOICE_CANCEL;
    RecoveryForm.ShowModal;
    Result := UserRecoveryChoice;
  finally
    RecoveryForm.Free;
  end;
end;

// Post-Install step: Run the Go installer engine with live progress
procedure CurStepChanged(CurStep: TSetupStep);
var
  EnginePath: string;
  InstallCmd: string;
  OutputStr: string;
  ResCode: Integer;
  SharePath: string;
  UserChoice: Integer;
  KeepRetrying: Boolean;
begin
  if CurStep = ssPostInstall then
  begin
    InstallSucceeded := False;
    InstallErrorMessage := '';
    EnginePath := ExpandConstant('{app}\altr-installer-engine.exe');
    WizardForm.StatusLabel.Caption := 'Initializing Altr Stream runtime setup...';

    // Delete any old diagnostic log from a previous installation/test run
    // so this run starts with a clean slate (Attempt 1)
    DeleteFile(ExpandConstant('{app}\.docker_start.log'));
    DeleteFile(ExpandConstant('{tmp}\engine_out.txt'));
    DeleteFile(ExpandConstant('{tmp}\install_out.txt'));

    InstallCmd := 'install --target-dir "' + ExpandConstant('{app}') + '"' +
                  ' --image "{#MyDockerImage}"' +
                  ' --version "{#MyAppVersion}"' +
                  ' --port 8000';
    if ShouldReplaceExisting then
      InstallCmd := InstallCmd + ' --replace-existing';

    KeepRetrying := True;
    while KeepRetrying do
    begin
      ResCode := RunEngineWithProgress(EnginePath, InstallCmd, OutputStr);

      if ResCode = 0 then
      begin
        InstallSucceeded := True;
        KeepRetrying := False;
        WizardForm.ProgressGauge.Position := 100;
        WizardForm.StatusLabel.Caption := 'Altr Stream started and verified successfully.';
      end
      else if (ResCode = 2) or IsFileSharingRequired(OutputStr, SharePath) then
      begin
        if SharePath = '' then
          SharePath := ExpandConstant('{app}\data\updates');

        UserChoice := ShowFileSharingRecoveryDialog(SharePath, OutputStr);
        if UserChoice = CHOICE_RETRY then
        begin
          WizardForm.StatusLabel.Caption := 'Retrying container startup with Docker file sharing...';
          ProcessSystemMessages;
          WizardForm.Refresh;
          KeepRetrying := True;
        end
        else
        begin
          KeepRetrying := False;
          InstallSucceeded := False;
          InstallErrorMessage :=
            'Docker Desktop file sharing permission was not granted for:' + #13#10 +
            '  ' + SharePath + #13#10#13#10 +
            'Please add this directory in Docker Desktop (Settings > Resources > File Sharing),' + #13#10 +
            'click "Apply & restart", and run "Altr Stream Repair" from the Start Menu.';
        end;
      end
      else
      begin
        KeepRetrying := False;
        InstallSucceeded := False;
        InstallErrorMessage := Trim(OutputStr);
        if InstallErrorMessage = '' then
          InstallErrorMessage := 'Container setup failed or timed out during initialization.';

        if MsgBox('Installation encountered an issue during container setup:' + #13#10#13#10 +
                  InstallErrorMessage + #13#10#13#10 +
                  'Would you like to open the container log file now for details?',
                  mbError, MB_YESNO) = IDYES then
        begin
          Exec(ExpandConstant('{cmd}'),
            '/c start notepad.exe "' + ExpandConstant('{app}\.docker_start.log') + '"',
            '', SW_HIDE, ewNoWait, ResCode);
        end;
      end;
    end;
  end;
end;


// Uninstaller step: Prompt for data volume retention
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  EnginePath: string;
  UninstCmd: string;
  OutputStr: string;
  DeleteData: Boolean;
begin
  if CurUninstallStep = usUninstall then
  begin
    EnginePath := ExpandConstant('{app}\altr-installer-engine.exe');
    if FileExists(EnginePath) then
    begin
      DeleteData := False;
      if MsgBox('Do you want to permanently delete your Altr Stream application data?' + #13#10#13#10 +
                'Selecting "Yes" permanently destroys the Docker volume "altr_stream_data".' + #13#10 +
                'Selecting "No" keeps your data safe for future reinstalls.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        DeleteData := True;
      end;

      if DeleteData then
        UninstCmd := 'uninstall --target-dir "' + ExpandConstant('{app}') + '" --delete-data'
      else
        UninstCmd := 'uninstall --target-dir "' + ExpandConstant('{app}') + '"';

      RunEngineCapture(EnginePath, UninstCmd, OutputStr);
    end;
  end;
end;
