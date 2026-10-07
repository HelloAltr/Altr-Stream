@echo off
rem ==============================================================================
rem  Altr Stream — Windows Setup & Management Utility
rem ==============================================================================
rem  Self-contained application-grade setup utility for Windows.
rem  Contains the embedded PowerShell installation engine.
rem
rem  Usage:
rem    Double-click this file in Windows Explorer, or execute from Command Prompt.
rem ==============================================================================

setlocal DisableDelayedExpansion

title Altr Stream Windows Setup

rem Configure comfortable console dimensions for Gum interactive TUI
mode con: cols=120 lines=35 >nul 2>&1

rem Remember launcher directory for locating bundled resources (e.g. bin\gum.exe)
set "ALTR_STREAM_LAUNCHER_DIR=%~dp0"
set "BAT_FILE=%~f0"

rem Locate PowerShell executable (prefers Windows PowerShell 5.1, falls back to pwsh.exe)
set "PS_EXE="
where powershell.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set "PS_EXE=powershell.exe"
) else (
    where pwsh.exe >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        set "PS_EXE=pwsh.exe"
    ) else if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
        set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
    )
)

if not defined PS_EXE (
    echo.
    echo ==============================================================================
    echo  ERROR: PowerShell Not Found
    echo ==============================================================================
    echo.
    echo  Altr Stream Setup requires Windows PowerShell 5.1 or PowerShell 7+.
    echo  Neither "powershell.exe" nor "pwsh.exe" was found on this system.
    echo.
    echo  Please ensure Windows PowerShell is installed and available in your PATH.
    echo.
    echo Press any key to exit.
    pause >nul
    exit /b 1
)

rem Define a unique temporary file path for the extracted PowerShell payload
set "TEMP_PS1=%TEMP%\AltrStream_Installer_%RANDOM%_%RANDOM%.ps1"

rem Extract the embedded PowerShell payload from this BAT file using the marker
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "$src = $env:BAT_FILE; $dst = $env:TEMP_PS1; $raw = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8); $marker = ':::POWERSHELL_' + 'PAYLOAD_START:::'; $idx = $raw.LastIndexOf($marker); if ($idx -ge 0) { [System.IO.File]::WriteAllText($dst, $raw.Substring($idx + $marker.Length).TrimStart(), [System.Text.Encoding]::UTF8); exit 0 } else { exit 1 }"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ==============================================================================
    echo  ERROR: Corrupted Installer Package
    echo ==============================================================================
    echo.
    echo  The embedded installation engine could not be extracted from:
    echo    "%BAT_FILE%"
    echo.
    echo  Please redownload Altr-Stream_Windows_Installer.bat from:
    echo    https://github.com/HelloAltr/Altr-Stream/releases/latest
    echo.
    if exist "%TEMP_PS1%" del /f /q "%TEMP_PS1%" >nul 2>&1
    echo Press any key to exit.
    pause >nul
    exit /b 1
)

rem Execute the extracted installer engine with forwarded CLI arguments
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%TEMP_PS1%" %*
set "INSTALLER_EXIT_CODE=%ERRORLEVEL%"

rem Clean up temporary installer payload
if exist "%TEMP_PS1%" del /f /q "%TEMP_PS1%" >nul 2>&1

rem If installer failed or exited abnormally, keep window open so user can inspect error
if %INSTALLER_EXIT_CODE% neq 0 (
    echo.
    echo ==============================================================================
    echo  ERROR: Altr Stream Windows Installer exited with an error.
    echo ==============================================================================
    echo.
    echo  The installer exited with error code: %INSTALLER_EXIT_CODE%
    echo.
    echo  If you need assistance, please submit an issue at:
    echo    https://github.com/HelloAltr/Altr-Stream/issues
    echo.
    echo Press any key to exit.
    pause >nul
    exit /b %INSTALLER_EXIT_CODE%
)

exit /b 0

:::POWERSHELL_PAYLOAD_START:::
<#
.SYNOPSIS
    Altr Stream — Windows Setup Utility
.DESCRIPTION
    Application-grade Terminal Setup Utility powered by Charmbracelet Gum for Windows:
    Install, Uninstall, Repair, and Status.
.PARAMETER Action
    Optional direct action: Install, Uninstall, Repair, Status, or Menu (default).
.PARAMETER Version
    The version of Altr Stream. Defaults to 1.0.0-beta.
.PARAMETER InstallPath
    Target directory for Altr Stream runtime and data. Defaults to $HOME\.altr-stream.
.EXAMPLE
    Altr-Stream_Windows_Installer.bat
#>

[CmdletBinding()]
param (
    [ValidateSet("Menu", "Install", "Uninstall", "Repair", "Status")]
    [string]$Action = "Menu",
    [string]$Version = "1.0.0-beta",
    [string]$InstallPath = ""
)

$ErrorActionPreference = "Stop"

# TEMPORARY E2E TEST OVERRIDE: Pull currently published 0.13.7-alpha image while 1.0.0-beta is pending release
$AltrImage = "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"
$DefaultDir = Join-Path $env:USERPROFILE ".altr-stream"
$ConfigFile = if ($env:ALTR_STREAM_CONFIG_FILE -and $env:ALTR_STREAM_CONFIG_FILE.Trim() -ne "") {
    $env:ALTR_STREAM_CONFIG_FILE
} else {
    Join-Path $env:USERPROFILE ".altr-stream-config"
}

$GumPinnedVersion = "2.0.2"
$GumWindowsX64Sha = "0397091dec9b4e8f00e02b90fd3eb07bf45acabbdb61d67437950f18e03a8b79"
$GumBin = ""

# ------------------------------------------------------------------------------
# Directory Management
# ------------------------------------------------------------------------------
function Get-InstallDirectory {
    if ($InstallPath -and $InstallPath.Trim() -ne "") {
        return [System.IO.Path]::GetFullPath($InstallPath)
    }
    if ($env:ALTR_STREAM_HOME -and $env:ALTR_STREAM_HOME.Trim() -ne "") {
        return [System.IO.Path]::GetFullPath($env:ALTR_STREAM_HOME)
    }
    if (Test-Path $ConfigFile) {
        $saved = (Get-Content -Path $ConfigFile -Raw -ErrorAction SilentlyContinue)
        if ($saved) {
            $saved = $saved.Trim()
            if ($saved -and (Test-Path $saved) -and (Test-Path (Join-Path $saved "docker-compose.yml"))) {
                if ($saved -notmatch "pytest|\\tmp\\|\\Temp\\|/tmp/|/var/") {
                    return [System.IO.Path]::GetFullPath($saved)
                }
            }
        }
    }
    return [System.IO.Path]::GetFullPath($DefaultDir)
}

function Save-InstallDirectory ([string]$path) {
    if ($path -match "pytest|\\tmp\\|\\Temp\\|/tmp/|/var/") {
        if ($env:ALTR_STREAM_CONFIG_FILE) {
            Set-Content -Path $ConfigFile -Value $path -Encoding UTF8 -Force -ErrorAction SilentlyContinue
        }
    } else {
        Set-Content -Path $ConfigFile -Value $path -Encoding UTF8 -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------------------
# Gum Dependency Resolution
# ------------------------------------------------------------------------------
function Resolve-Gum {
    # 1. Bundled next to launcher BAT or script (e.g. within release zip: Altr-Stream_Windows_Installer.bat + bin\gum.exe)
    $scriptDir = if ($env:ALTR_STREAM_LAUNCHER_DIR -and (Test-Path $env:ALTR_STREAM_LAUNCHER_DIR)) {
        $env:ALTR_STREAM_LAUNCHER_DIR
    } elseif ($PSScriptRoot) {
        $PSScriptRoot
    } elseif ($PSCommandPath) {
        Split-Path -Parent $PSCommandPath
    } else {
        $PWD.Path
    }
    if ($scriptDir) {
        $bundledGum = Join-Path $scriptDir "bin\gum.exe"
        if (Test-Path $bundledGum) {
            $script:GumBin = $bundledGum
            return $true
        }
    }

    # 2. System PATH
    $pathGum = Get-Command "gum.exe" -ErrorAction SilentlyContinue
    if ($pathGum) {
        $script:GumBin = $pathGum.Source
        return $true
    }

    # 3. User local cache
    $cacheDir = Join-Path $env:LOCALAPPDATA "AltrStream\bin"
    $cacheGum = Join-Path $cacheDir "gum.exe"
    if (Test-Path $cacheGum) {
        $script:GumBin = $cacheGum
        return $true
    }

    # 4. Verified download from official Charmbracelet release
    $downloadUrl = "https://github.com/charmbracelet/gum/releases/download/v$GumPinnedVersion/gum_${GumPinnedVersion}_Windows_x86_64.zip"
    $tempZip = Join-Path $env:TEMP "gum_${GumPinnedVersion}_Windows_x86_64.zip"
    $tempExtract = Join-Path $env:TEMP "gum_extract_$GumPinnedVersion"

    Write-Host "Preparing Altr Stream Setup UI (fetching Gum v$GumPinnedVersion)..." -ForegroundColor Cyan
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing

        $hashObj = Get-FileHash -Path $tempZip -Algorithm SHA256
        $actualSha = $hashObj.Hash.ToLower()
        if ($actualSha -ne $GumWindowsX64Sha.ToLower()) {
            Write-Error "ERROR: Gum binary verification failed! Checksum mismatch."
            Write-Error "Expected: $GumWindowsX64Sha"
            Write-Error "Actual:   $actualSha"
            Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
            return $false
        }

        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        $foundGum = Get-ChildItem -Path $tempExtract -Filter "gum.exe" -Recurse | Select-Object -First 1
        if ($foundGum) {
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            Copy-Item -Path $foundGum.FullName -Destination $cacheGum -Force
            Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
            $script:GumBin = $cacheGum
            return $true
        }
    }
    catch {
        Write-Warning "Could not download Gum automatically: $_"
        return $false
    }
    return $false
}

# ------------------------------------------------------------------------------
# Terminal Dimension & Sizing Helpers
# ------------------------------------------------------------------------------
$MinTermCols = 100
$MinTermLines = 30

function Get-TermDimensions {
    $cols = 80
    $lines = 24
    try {
        if ($Host -and $Host.UI -and $Host.UI.RawUI) {
            $cols = $Host.UI.RawUI.WindowSize.Width
            $lines = $Host.UI.RawUI.WindowSize.Height
        }
    } catch {}
    if ($cols -le 0) { $cols = 80 }
    if ($lines -le 0) { $lines = 24 }
    return @($cols, $lines)
}

function Get-LayoutPadding([int]$cardWidth = 68, [int]$estHeight = 20) {
    $dims = Get-TermDimensions
    $cols = $dims[0]
    $lines = $dims[1]

    $leftPad = [Math]::Max(0, [int][Math]::Floor(($cols - $cardWidth) / 2))
    $topPad = [Math]::Max(0, [int][Math]::Floor(($lines - $estHeight) / 2))
    return @($leftPad, $topPad)
}

function Check-TerminalSize {
    if (-not $GumBin -or ($Action -ne "Menu")) { return }
    $dims = Get-TermDimensions
    $cols = $dims[0]
    $lines = $dims[1]

    if ($cols -ge $MinTermCols -and $lines -ge $MinTermLines) {
        return
    }

    while ($cols -lt $MinTermCols -or $lines -lt $MinTermLines) {
        Clear-Host
        $cardW = 60
        $leftPad = [Math]::Max(0, [int][Math]::Floor(($cols - $cardW) / 2))
        $topPad = [Math]::Max(0, [int][Math]::Floor(($lines - 14) / 2))

        for ($i = 0; $i -lt $topPad; $i++) { Write-Host "" }

        try {
            Invoke-GumStyle --margin "0 0 0 $leftPad" --border double --border-foreground 214 --padding "1 2" --width $cardW --align center --bold `
                "ALTR STREAM" "Setup & Management Utility" "" `
                "⚠ Terminal window is too small." "" `
                "Current:  $cols × $lines" `
                "Required: $MinTermCols × $MinTermLines" "" `
                "Please resize the terminal window."
        } catch {
            Write-Host "`n  ALTR STREAM`n  Setup & Management Utility`n`n  Terminal window is too small.`n  Current: $cols × $lines`n  Required: $MinTermCols × $MinTermLines`n`n  Please resize the terminal window."
        }

        Start-Sleep -Milliseconds 500
        $dims = Get-TermDimensions
        $cols = $dims[0]
        $lines = $dims[1]
    }
    Clear-Host
}

function Render-ScreenTop([int]$estHeight = 20) {
    Check-TerminalSize
    $pad = Get-LayoutPadding 68 $estHeight
    $topPad = $pad[1]
    Clear-Host
    for ($i = 0; $i -lt $topPad; $i++) {
        Write-Host ""
    }
}

function Get-ViewportSelPad {
    param([int]$customLeftPad = -1)
    if ($customLeftPad -ge 0) {
        $lpad = $customLeftPad
    } elseif ($null -ne (Get-Variable -Name "leftPad" -Scope 1 -ErrorAction SilentlyContinue)) {
        $lpad = (Get-Variable -Name "leftPad" -Scope 1).Value
    } else {
        $pad = Get-LayoutPadding 68 20
        $lpad = $pad[0]
    }
    $selPad = [int]$lpad + 2
    if ($selPad -lt 0) { $selPad = 0 }
    return $selPad
}

# ------------------------------------------------------------------------------
# Robust Gum UI & Styling Layer with Plain-Text Fallback
# Guarantees that cosmetic styling errors or unknown flags never crash the installer
# or leak raw Gum help/usage text to the terminal.
# ------------------------------------------------------------------------------
function Format-TechnicalLines([string]$text, [int]$maxLines = 4, [int]$maxLen = 60) {
    if (-not $text) { return @() }
    $out = @()
    $raw = ($text -split "`r?`n") | Where-Object { $_ -and $_.Trim() }
    foreach ($line in ($raw | Select-Object -First $maxLines)) {
        $t = $line.Trim()
        if ($t.Length -gt $maxLen) { $t = $t.Substring(0, $maxLen - 3) + "..." }
        $out += "  {0}" -f $t
    }
    return $out
}

function Fallback-RenderStyle {
    param(
        [string[]]$Flags = @(),
        [string[]]$Lines = @()
    )

    $leftPad = 0
    $width = 68
    $hasBorder = $false
    $color = "White"

    for ($idx = 0; $idx -lt $Flags.Length; $idx++) {
        $fl = $Flags[$idx]
        if ($fl -eq "--margin" -and ($idx + 1) -lt $Flags.Length) {
            $mParts = $Flags[$idx + 1] -split "\s+"
            if ($mParts.Length -ge 4) { [int]::TryParse($mParts[3], [ref]$leftPad) | Out-Null }
        }
        if ($fl -eq "--width" -and ($idx + 1) -lt $Flags.Length) {
            [int]::TryParse($Flags[$idx + 1], [ref]$width) | Out-Null
        }
        if ($fl -eq "--border") { $hasBorder = $true }
        if ($fl -in @("--foreground", "--border-foreground") -and ($idx + 1) -lt $Flags.Length) {
            $cVal = $Flags[$idx + 1]
            if ($cVal -in @("196", "9")) { $color = "Red" }
            elseif ($cVal -in @("48", "10", "46")) { $color = "Green" }
            elseif ($cVal -in @("214", "11", "208", "220")) { $color = "Yellow" }
            elseif ($cVal -in @("39", "12", "33", "27")) { $color = "Cyan" }
            elseif ($cVal -in @("245", "240", "8", "7")) { $color = "DarkGray" }
        }
    }

    $padStr = if ($leftPad -gt 0) { " " * $leftPad } else { "" }

    if ($hasBorder) {
        $innerW = [Math]::Max(10, $width - 4)
        $topBorder = "{0}┌{1}┐" -f $padStr, ("─" * ($innerW + 2))
        $botBorder = "{0}└{1}┘" -f $padStr, ("─" * ($innerW + 2))
        Write-Host $topBorder -ForegroundColor $color
        foreach ($line in $Lines) {
            $text = if ($null -ne $line) { [string]$line } else { "" }
            if ($text.Length -gt $innerW) { $text = $text.Substring(0, $innerW - 3) + "..." }
            $linePad = " " * [Math]::Max(0, ($innerW - $text.Length))
            Write-Host ("{0}│ {1}{2} │" -f $padStr, $text, $linePad) -ForegroundColor $color
        }
        Write-Host $botBorder -ForegroundColor $color
    } else {
        foreach ($line in $Lines) {
            $text = if ($null -ne $line) { [string]$line } else { "" }
            Write-Host ("{0}{1}" -f $padStr, $text) -ForegroundColor $color
        }
    }
}

function Invoke-GumStyle {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$StyleArgs
    )

    if (-not $StyleArgs -or $StyleArgs.Count -eq 0) { return }

    $flagsWithValues = @(
        "--foreground", "--background", "--border", "--border-background",
        "--border-foreground", "--align", "--height", "--width", "--margin", "--padding"
    )
    $switchFlags = @(
        "--bold", "--faint", "--italic", "--strikethrough", "--underline",
        "--trim", "--strip-ansi", "--no-strip-ansi"
    )

    $gumFlags = @()
    $textLines = @()
    $i = 0
    $parsingFlags = $true

    while ($i -lt $StyleArgs.Count) {
        $arg = $StyleArgs[$i]
        if ($parsingFlags -and ($arg -is [string])) {
            if ($arg -eq "--") {
                $parsingFlags = $false
                $i++
                continue
            }
            if ($flagsWithValues -contains $arg) {
                $gumFlags += $arg
                if (($i + 1) -lt $StyleArgs.Count) {
                    $gumFlags += [string]$StyleArgs[$i + 1]
                    $i += 2
                    continue
                } else {
                    $i++
                    continue
                }
            }
            if ($switchFlags -contains $arg) {
                $gumFlags += $arg
                $i++
                continue
            }
            $parsingFlags = $false
        } else {
            $parsingFlags = $false
        }

        if ($arg -is [System.Collections.IEnumerable] -and $arg -isnot [string]) {
            foreach ($sub in $arg) {
                if ($null -ne $sub) { $textLines += [string]$sub }
            }
        } else {
            if ($null -ne $arg) { $textLines += [string]$arg }
        }
        $i++
    }

    if ($script:GumBin -and (Test-Path $script:GumBin)) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        try {
            # Kong/Gum requires "--" before positional text arguments so tokens like "-f" or dashes
            # in command outputs are never parsed as flags. Stderr is redirected to $null so internal
            # errors never leak raw usage/help text into the interactive console.
            $rendered = if ($textLines.Count -gt 0) {
                & $script:GumBin style @gumFlags "--" @textLines 2>$null
            } else {
                & $script:GumBin style @gumFlags 2>$null
            }

            if ($LASTEXITCODE -eq 0 -and $null -ne $rendered) {
                $rendered | ForEach-Object { Write-Host $_ }
                $ErrorActionPreference = $prevEAP
                return
            }
        }
        catch {}
        finally {
            $ErrorActionPreference = $prevEAP
        }
    }

    Fallback-RenderStyle -Flags $gumFlags -Lines $textLines
}

function Invoke-GumChoose {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $selPad = Get-ViewportSelPad
    if ($script:GumBin -and (Test-Path $script:GumBin)) {
        try {
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "SilentlyContinue"
            $res = & $script:GumBin choose --padding="0 0 0 $selPad" @Args 2>$null
            $code = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            if ($code -eq 0 -and $null -ne $res -and "$res".Trim() -ne "") {
                return "$res".Trim()
            }
        } catch {
            $ErrorActionPreference = $prevEAP
        }
    }

    # Plain text console fallback
    $options = @()
    $header = "Select an option:"
    for ($idx = 0; $idx -lt $Args.Length; $idx++) {
        $a = $Args[$idx]
        if ($a -match "^--header=(.*)") {
            $header = $matches[1]
        } elseif ($a -match "^--cursor|^--padding") {
            # Skip presentation flag
        } else {
            if ($a -is [System.Collections.IEnumerable] -and $a -isnot [string]) {
                foreach ($sub in $a) { if ($sub) { $options += [string]$sub } }
            } else {
                if ($a) { $options += [string]$a }
            }
        }
    }

    if ($options.Count -eq 0) { return "" }
    Write-Host ""
    Write-Host ("  {0}" -f $header) -ForegroundColor Cyan
    for ($idx = 0; $idx -lt $options.Count; $idx++) {
        Write-Host ("    {0}. {1}" -f ($idx + 1), $options[$idx])
    }
    while ($true) {
        $sel = Read-Host ("  Enter choice (1-{0}): " -f $options.Count)
        [int]$num = 0
        if ([int]::TryParse($sel, [ref]$num) -and $num -ge 1 -and $num -le $options.Count) {
            return $options[$num - 1]
        }
        Write-Host ("  Invalid choice. Please enter a number between 1 and {0}." -f $options.Count) -ForegroundColor Yellow
    }
}

function Invoke-GumConfirm {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $selPad = Get-ViewportSelPad
    if ($script:GumBin -and (Test-Path $script:GumBin)) {
        try {
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "SilentlyContinue"
            & $script:GumBin confirm --padding="0 0 0 $selPad" @Args 2>$null
            $code = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            return ($code -eq 0)
        } catch {
            $ErrorActionPreference = $prevEAP
        }
    }

    # Plain text console fallback
    $prompt = "Confirm action?"
    foreach ($a in $Args) {
        if ($a -notmatch "^--") { $prompt = [string]$a; break }
    }
    $ans = Read-Host ("  {0} [y/N]: " -f $prompt)
    return ($ans -match "^(?i)y")
}

function Invoke-GumInput {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    $selPad = Get-ViewportSelPad
    if ($script:GumBin -and (Test-Path $script:GumBin)) {
        try {
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "SilentlyContinue"
            $res = & $script:GumBin input --padding="0 0 0 $selPad" @Args 2>$null
            $code = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            if ($code -eq 0 -and $null -ne $res) {
                return "$res".Trim()
            }
        } catch {
            $ErrorActionPreference = $prevEAP
        }
    }

    # Plain text console fallback
    $prompt = "Enter value"
    $defaultVal = ""
    for ($idx = 0; $idx -lt $Args.Length; $idx++) {
        $a = $Args[$idx]
        if ($a -match "^--placeholder=(.*)") { $prompt = $matches[1] }
        elseif ($a -match "^--value=(.*)") { $defaultVal = $matches[1] }
    }
    $promptStr = if ($defaultVal) {
        "  {0} [{1}]: " -f $prompt, $defaultVal
    } else {
        "  {0}: " -f $prompt
    }
    $in = Read-Host $promptStr
    if (-not $in -and $defaultVal) { return $defaultVal }
    return $in
}


# ------------------------------------------------------------------------------
# Safe Native Docker Execution Layer
# Prevents $ErrorActionPreference = "Stop" from converting expected non-zero exits
# or stderr text into fatal terminating NativeCommandError exceptions in PS 5.1.
# ------------------------------------------------------------------------------
function Invoke-DockerCliSafe {
    param(
        [string]$Arguments,
        [int]$TimeoutSec = 15
    )
    $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
    if (-not $dockerCmd) {
        return [PSCustomObject]@{
            ExitCode = -1
            Output = ""
            Error = "docker command not found"
            Success = $false
        }
    }

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "docker"
        $psi.Arguments = $Arguments
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $p = [System.Diagnostics.Process]::Start($psi)
        if ($p.WaitForExit($TimeoutSec * 1000)) {
            $stdout = $p.StandardOutput.ReadToEnd()
            $stderr = $p.StandardError.ReadToEnd()
            return [PSCustomObject]@{
                ExitCode = $p.ExitCode
                Output = $stdout.Trim()
                Error = $stderr.Trim()
                Success = ($p.ExitCode -eq 0)
            }
        } else {
            try { $p.Kill() } catch {}
            return [PSCustomObject]@{
                ExitCode = -1
                Output = ""
                Error = "docker command timed out after $TimeoutSec seconds"
                Success = $false
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            ExitCode = -1
            Output = ""
            Error = $_.Exception.Message
            Success = $false
        }
    }
}

function Get-ContainerInspectField([string]$ContainerName, [string]$Format) {
    if (-not $ContainerName) { return "" }
    $cleanFormat = $Format.Trim(" '`"`t`r`n")
    $res = Invoke-DockerCliSafe "inspect -f `"$cleanFormat`" $ContainerName"
    if ($res.Success) {
        return $res.Output
    }
    return ""
}

function Test-ContainerExists([string]$ContainerName = "altr-stream") {
    if (-not $ContainerName) { return $false }
    $res = Invoke-DockerCliSafe "inspect $ContainerName"
    return $res.Success
}

# ------------------------------------------------------------------------------
# Docker & Compose Diagnostics & Checks
# ------------------------------------------------------------------------------
function Get-ComposeCommand {
    $res1 = Invoke-DockerCliSafe "compose version" 5
    if ($res1.Success) { return "docker compose" }

    $composeCmd = Get-Command "docker-compose" -ErrorAction SilentlyContinue
    if ($composeCmd) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "docker-compose"
            $psi.Arguments = "version"
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            if ($p.WaitForExit(5000) -and $p.ExitCode -eq 0) {
                return "docker-compose"
            }
        } catch {}
    }

    return ""
}

function Get-DockerDiagnostics {
    $diag = @{
        CliInstalled = $false
        DesktopInstalled = $false
        EngineRunning = $false
        ComposeAvailable = $false
        ComposeCommand = ""
        StatusText = "Not Installed"
        ActionHint = "Install Docker Desktop"
        TechnicalError = ""
        FailureReason = ""
    }

    # 1. Resolve Docker CLI binary
    $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
    if (-not $dockerCmd) {
        $commonBins = @(
            "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
            "${env:ProgramFiles(x86)}\Docker\Docker\resources\bin\docker.exe"
        )
        foreach ($bin in $commonBins) {
            if ($bin -and (Test-Path $bin)) {
                $binDir = Split-Path -Parent $bin
                $env:PATH = "$binDir;$env:PATH"
                $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
                break
            }
        }
    }

    if ($dockerCmd) {
        $diag.CliInstalled = $true
    }

    # 2. Resolve Docker Desktop GUI application
    $desktopExes = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    )
    if ($dockerCmd -and $dockerCmd.Source) {
        try {
            $pRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $dockerCmd.Source))
            if ($pRoot) { $desktopExes += (Join-Path $pRoot "Docker Desktop.exe") }
        } catch {}
    }
    foreach ($exe in $desktopExes) {
        if ($exe -and (Test-Path $exe)) {
            $diag.DesktopInstalled = $true
            break
        }
    }
    if (-not $diag.DesktopInstalled) {
        $shortcuts = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk",
            "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk"
        )
        foreach ($lnk in $shortcuts) {
            if ($lnk -and (Test-Path $lnk)) {
                $diag.DesktopInstalled = $true
                break
            }
        }
    }

    # If neither CLI nor Desktop is found:
    if (-not $diag.CliInstalled -and -not $diag.DesktopInstalled) {
        $diag.StatusText = "Not Installed"
        $diag.ActionHint = "Install Docker Desktop"
        $diag.FailureReason = "Docker was not found on this system."
        return $diag
    }

    # 3. Probe Docker Engine (docker info) without spawning windows
    if ($diag.CliInstalled) {
        $maxAttempts = 1
        $desktopProc = Get-Process "Docker Desktop" -ErrorAction SilentlyContinue
        if ($desktopProc) {
            $maxAttempts = 3
        }

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            $res = Invoke-DockerCliSafe "info" 5
            $diag.TechnicalError = ($res.Error + "`n" + $res.Output).Trim()
            if ($res.Success) {
                $diag.EngineRunning = $true
                break
            }
            if ($attempt -lt $maxAttempts) {
                Start-Sleep -Seconds 2
            }
        }
    }

    # 4. Probe Compose
    $composeCmd = Get-ComposeCommand
    if ($composeCmd) {
        $diag.ComposeAvailable = $true
        $diag.ComposeCommand = $composeCmd
    }

    # 5. Determine Final StatusText and ActionHint
    if ($diag.EngineRunning) {
        if ($diag.ComposeAvailable) {
            $diag.StatusText = "Ready"
            $diag.ActionHint = ""
            return $diag
        } else {
            $diag.StatusText = "No Compose"
            $diag.ActionHint = "Install Docker Compose v2"
            $diag.FailureReason = "Docker Engine is running, but Docker Compose plugin was not found."
            return $diag
        }
    }

    # Engine is NOT running: diagnose why
    $rawTech = $diag.TechnicalError
    if ($rawTech -match "(?i)virtualization|hyper-v|hypervisor|wsl|nested|required feature|vmcompute") {
        $diag.StatusText = "Unavailable"
        $diag.ActionHint = "Enable Virtualization / WSL 2"
        $diag.FailureReason = "Docker Desktop is installed, but virtualization or WSL 2 is unavailable in this environment."
    } elseif ($rawTech -match "(?i)daemon is not running|error during connect|cannot connect to the docker daemon|npipe://") {
        $diag.StatusText = "Not Running"
        $diag.ActionHint = "Start Docker Desktop"
        $diag.FailureReason = "Docker is installed, but Docker Engine is not currently running."
    } elseif ($diag.DesktopInstalled -and -not $diag.CliInstalled) {
        $diag.StatusText = "Not Running"
        $diag.ActionHint = "Start Docker Desktop"
        $diag.FailureReason = "Docker Desktop was found, but Docker CLI tools are not in PATH or daemon is stopped."
    } else {
        $diag.StatusText = "Unavailable"
        $diag.ActionHint = "Start/Fix Docker Desktop"
        $diag.FailureReason = if ($rawTech) {
            ($rawTech -split "`r?`n")[0].Trim()
        } else {
            "Docker Engine is not running or accessible."
        }
    }

    return $diag
}

function Test-DockerEngine {
    $diag = Get-DockerDiagnostics
    return ($diag.EngineRunning -and $diag.ComposeAvailable)
}

function Get-DockerStatusText {
    $diag = Get-DockerDiagnostics
    return $diag.StatusText
}

function Start-DockerDesktopProcess {
    $desktopExes = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    )
    $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
    if ($dockerCmd -and $dockerCmd.Source) {
        try {
            $pRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $dockerCmd.Source))
            if ($pRoot) { $desktopExes += (Join-Path $pRoot "Docker Desktop.exe") }
        } catch {}
    }
    foreach ($exe in $desktopExes) {
        if ($exe -and (Test-Path $exe)) {
            try {
                Start-Process -FilePath $exe
                return $true
            }
            catch {}
        }
    }
    $shortcuts = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk",
        "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Docker Desktop.lnk"
    )
    foreach ($lnk in $shortcuts) {
        if ($lnk -and (Test-Path $lnk)) {
            try {
                Start-Process -FilePath $lnk
                return $true
            }
            catch {}
        }
    }
    return $false
}

function Get-WebPort([string]$dir = "") {
    if (-not $dir) { $dir = Get-InstallDirectory }
    $envFile = Join-Path $dir ".env"
    if (Test-Path $envFile) {
        $lines = Get-Content $envFile
        foreach ($l in $lines) {
            if ($l -match "^\s*ALTR_STREAM_PORT\s*=\s*(.+)$") {
                $val = $matches[1].Trim()
                $val = $val.Trim('"')
                $val = $val.Trim("'")
                if ($val) { return $val }
            }
        }
    }
    return "8000"
}

function Get-WebUrl([string]$dir = "") {
    $port = Get-WebPort $dir
    return "http://localhost:$port"
}

function Invoke-LaunchBrowser([string]$url) {
    try {
        Start-Process $url
    }
    catch {
        Write-Warning "Could not automatically open default browser for $url"
    }
}

function Get-AltrStatusText ([string]$dir = "") {
    if (-not $dir) { $dir = Get-InstallDirectory }
    if (-not (Test-Path (Join-Path $dir "docker-compose.yml"))) {
        return "Not Installed"
    }
    $webUrl = Get-WebUrl $dir
    try {
        $resp = Invoke-RestMethod -Uri "$webUrl/api/v1/health" -TimeoutSec 1 -ErrorAction SilentlyContinue
        if ($resp) { return "Running" }
    }
    catch {}

    try {
        $compose = Get-ComposeCommand
        if ($compose) {
            $psOut = Invoke-Expression "$compose -f `"$dir\docker-compose.yml`" ps --status running" 2>$null
            if ($psOut -match "altr-stream") { return "Running" }
            $psAll = Invoke-Expression "$compose -f `"$dir\docker-compose.yml`" ps -a" 2>$null
            if ($psAll -match "altr-stream") { return "Stopped" }
        }
    }
    catch {}

    $st = Get-ContainerInspectField "altr-stream" '{{.State.Status}}'
    if ($st -eq "running") { return "Running" }
    if ($st -eq "paused") { return "Paused" }
    if ($st -eq "restarting") { return "Restarting" }
    if ($st -eq "exited") { return "Stopped" }
    if ($st -eq "dead") { return "Stopped / Failed" }
    if ($st -eq "created") { return "Not Running / Stopped" }
    if ($st) { return "Stopped" }

    return "Not Installed"
}

function Test-InstallationHealth([string]$TargetDir) {
    if (-not (Test-Path $TargetDir)) { return $false }
    if (-not (Test-Path (Join-Path $TargetDir "docker-compose.yml"))) { return $false }
    if (-not (Test-Path (Join-Path $TargetDir ".env"))) { return $false }

    $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
    if (-not $dockerCmd) { return $false }

    $cstatus = Get-ContainerInspectField "altr-stream" '{{.State.Status}}'
    if ($cstatus -ne "running") { return $false }

    $cimage = Get-ContainerInspectField "altr-stream" '{{.Config.Image}}'
    if ($cimage -notmatch "altr-stream") { return $false }

    $cmounts = Get-ContainerInspectField "altr-stream" '{{range .Mounts}}{{.Name}} {{end}}'
    if ($cmounts -notmatch "altr_stream_data") { return $false }

    $webUrl = Get-WebUrl $TargetDir
    try {
        $resp = Invoke-RestMethod -Uri "$webUrl/api/v1/health" -TimeoutSec 2 -ErrorAction Stop
        if ($resp) { return $true }
    }
    catch {
        try {
            $resp = Invoke-RestMethod -Uri "$webUrl/api/health" -TimeoutSec 2 -ErrorAction Stop
            if ($resp) { return $true }
        }
        catch {
            return $false
        }
    }
    return $false
}

# ------------------------------------------------------------------------------
# Manifest Generation
# ------------------------------------------------------------------------------
function Write-RuntimeFiles ([string]$installDir) {
    if (-not (Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }
    $updatesDir = Join-Path $installDir "data\updates"
    if (-not (Test-Path $updatesDir)) {
        New-Item -ItemType Directory -Path $updatesDir -Force | Out-Null
    }

    $composeTemplate = @'
services:
  altr-stream:
    image: ghcr.io/helloaltr/altr-stream:__VERSION__
    container_name: altr-stream
    restart: unless-stopped
    ports:
      - "${ALTR_STREAM_PORT:-8000}:8000"
    volumes:
      - altr_stream_data:/app/data
      - ./data/updates:/app/data/updates
    environment:
      - ALTR_STREAM_HOST=0.0.0.0
      - ALTR_STREAM_PORT=8000
      - ALTR_STREAM_DATA_DIR=/app/data
      - ALTR_STREAM_DEBUG=${ALTR_STREAM_DEBUG:-false}
      - ALTR_STREAM_LOG_LEVEL=${ALTR_STREAM_LOG_LEVEL:-INFO}
      - ALTR_STREAM_DEFAULT_CONNECTION_TIMEOUT_SEC=${ALTR_STREAM_DEFAULT_CONNECTION_TIMEOUT_SEC:-5.0}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s

volumes:
  altr_stream_data:
    name: altr_stream_data
'@
    $composeContent = $composeTemplate.Replace("ghcr.io/helloaltr/altr-stream:__VERSION__", $AltrImage)

    $composePath = Join-Path $installDir "docker-compose.yml"
    Set-Content -Path $composePath -Value $composeContent -Encoding UTF8 -Force

    $envPath = Join-Path $installDir ".env"
    if (-not (Test-Path $envPath)) {
        $envContent = @"
# Altr Stream Environment Configuration
ALTR_STREAM_PORT=8000
ALTR_STREAM_LOG_LEVEL=INFO
ALTR_STREAM_DEBUG=false
ALTR_STREAM_DEFAULT_CONNECTION_TIMEOUT_SEC=5.0
"@
        Set-Content -Path $envPath -Value $envContent -Encoding UTF8 -Force
    }
}

# ------------------------------------------------------------------------------
# Screen: Docker Diagnostics & Error Handling
# ------------------------------------------------------------------------------
function Show-DockerTechnicalDetailsScreen ($diag) {
    if (-not $GumBin) { return }
    Render-ScreenTop 24
    $pad = Get-LayoutPadding 68 24
    $leftPad = $pad[0]

    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 --align center --bold `
        "DOCKER TECHNICAL DIAGNOSTICS"

    $lines = @(
        "Probe Results:",
        "  Docker CLI Detected:     $(if ($diag.CliInstalled) { 'Yes' } else { 'No' })",
        "  Docker Desktop Found:    $(if ($diag.DesktopInstalled) { 'Yes' } else { 'No' })",
        "  Engine Running:          $(if ($diag.EngineRunning) { 'Yes' } else { 'No' })",
        "  Compose Available:       $(if ($diag.ComposeAvailable) { 'Yes' } else { 'No' })",
        ""
    )
    if ($diag.TechnicalError) {
        $lines += "Raw Diagnostic Output:"
        $rawLines = ($diag.TechnicalError -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 8
        foreach ($rl in $rawLines) {
            $t = $rl.Trim()
            if ($t.Length -gt 60) { $t = $t.Substring(0, 57) + "..." }
            $lines += "  $t"
        }
    } else {
        $lines += "No raw error output captured from Docker CLI."
    }

    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 @lines

    Invoke-GumChoose --cursor="❯ " --header="" "Back to Diagnostics" | Out-Null
}

function Show-DockerDiagnosticScreen ($diag) {
    if (-not $GumBin) { return }

    while ($true) {
        Render-ScreenTop 24
        $pad = Get-LayoutPadding 68 24
        $leftPad = $pad[0]

        $headerTitle = switch ($diag.StatusText) {
            "Not Installed" { "Docker Required" }
            "Not Running"   { "Docker Engine Not Running" }
            "Unavailable"   { "Docker Engine Unavailable" }
            "No Compose"    { "Docker Compose Required" }
            default         { "Docker Engine Required" }
        }

        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 --align center --bold `
            "✕ $headerTitle" "" `
            "Altr Stream requires a running Docker Engine."

        # Diagnostic Details Card
        $card = @(
            "Diagnostic Details:", ""
        )

        if ($diag.StatusText -eq "Not Installed") {
            $card += "  Status:         Docker was not found on this system."
            $card += "  Action:         Please install Docker Desktop and start the engine."
            $card += "  Documentation:  https://docs.docker.com/desktop/setup/install/windows-install/"
        } elseif ($diag.StatusText -eq "Not Running") {
            $card += "  Status:         Docker is installed, but Docker Engine is not running."
            $card += "  Action:         Start Docker Desktop, wait for the engine to start,"
            $card += "                  and retry installation."
        } elseif ($diag.StatusText -eq "Unavailable") {
            $card += "  Status:         Docker is installed, but the engine could not start."
            if ($diag.TechnicalError -match "(?i)virtualization|hyper-v|hypervisor|wsl|nested|required feature|vmcompute") {
                $card += "  Root Cause:     Virtualization or WSL 2 is unavailable/disabled."
                $card += "  Action:         Enable virtualization in BIOS / hypervisor settings,"
                $card += "                  or configure WSL 2 and start Docker Desktop."
            } else {
                $card += "  Action:         Start or repair Docker Desktop and inspect its logs."
            }
        } elseif ($diag.StatusText -eq "No Compose") {
            $card += "  Status:         Docker Engine is running, but Docker Compose is missing."
            $card += "  Action:         Install Docker Compose v2 plugin."
        } else {
            $card += "  Status:         $($diag.FailureReason)"
            $card += "  Action:         $($diag.ActionHint)"
        }

        if ($diag.TechnicalError) {
            $tLines = ($diag.TechnicalError -split "`r?`n") | Where-Object { $_.Trim() }
            if ($tLines.Count -gt 0) {
                $card += ""
                $card += "Technical Details:"
                $sample = $tLines[0].Trim()
                if ($sample.Length -gt 60) { $sample = $sample.Substring(0, 57) + "..." }
                $card += "  $sample"
                if ($tLines.Count -gt 1) {
                    $sample2 = $tLines[1].Trim()
                    if ($sample2.Length -gt 60) { $sample2 = $sample2.Substring(0, 57) + "..." }
                    $card += "  $sample2"
                }
            }
        }

        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 @card

        # Interactive Options
        $options = @()
        if ($diag.DesktopInstalled) {
            $options += "Start Docker Desktop"
        }
        $options += @("Retry Detection", "View Technical Details", "Open Docker Guide", "Back to Main Menu")

        $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="What would you like to do?" @options

        switch ($choice) {
            "Start Docker Desktop" {
                $started = Start-DockerDesktopProcess
                if ($started) {
                    & $GumBin spin --spinner dot --title "Waiting for Docker Engine to start..." -- Start-Sleep -Seconds 5
                }
                $diag = Get-DockerDiagnostics
                if ($diag.EngineRunning -and $diag.ComposeAvailable) {
                    return
                }
            }
            "Retry Detection" {
                & $GumBin spin --spinner dot --title "Probing Docker Engine..." -- Start-Sleep -Seconds 1
                $diag = Get-DockerDiagnostics
                if ($diag.EngineRunning -and $diag.ComposeAvailable) {
                    return
                }
            }
            "View Technical Details" {
                Show-DockerTechnicalDetailsScreen $diag
            }
            "Open Docker Guide" {
                Start-Process "https://docs.docker.com/desktop/setup/install/windows-install/"
            }
            "Back to Main Menu" {
                return
            }
            default {
                return
            }
        }
    }
}

# ------------------------------------------------------------------------------
# Screen: Main Menu
# ------------------------------------------------------------------------------
function Show-MainMenu {
    while ($true) {
        Render-ScreenTop 22
        $pad = Get-LayoutPadding 68 22
        $leftPad = $pad[0]
        $targetDir = Get-InstallDirectory
        $diag = Get-DockerDiagnostics
        $dockerStat = $diag.StatusText
        $altrStat = Get-AltrStatusText $targetDir

        $innerW = 62
        $h1 = "ALTR STREAM"
        $h2 = "Setup & Management Utility"
        $h3 = "v$Version"
        $pad1 = [Math]::Max(0, [int][Math]::Floor(($innerW - $h1.Length) / 2))
        $pad2 = [Math]::Max(0, [int][Math]::Floor(($innerW - $h2.Length) / 2))
        $pad3 = [Math]::Max(0, [int][Math]::Floor(($innerW - $h3.Length) / 2))
        $sp1 = " " * $pad1
        $sp2 = " " * $pad2
        $sp3 = " " * $pad3

        # 1. Unified Application Viewport Container Card
        $cardLines = @(
            "${sp1}${h1}",
            "${sp2}${h2}",
            "${sp3}${h3}",
            "",
            "  Docker Engine:  $dockerStat",
            "  Altr Container: $altrStat",
            "  Install Path:   $targetDir"
        )
        if ($diag.ActionHint -and $diag.StatusText -ne "Ready") {
            $cardLines += "  Action:         $($diag.ActionHint)"
        }

        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 --bold @cardLines

        # 2. Interactive Selection (Aligned inside Centered Viewport)
        $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Select an operation:" `
            "Install Altr Stream" "Uninstall Altr Stream" "Repair Installation" "Installation Status" "Exit"

        switch ($choice) {
            "Install Altr Stream"   { Invoke-InstallWorkflow }
            "Uninstall Altr Stream" { Invoke-UninstallWorkflow }
            "Repair Installation"   { Invoke-RepairWorkflow }
            "Installation Status"   { Invoke-StatusWorkflow }
            default                 { Clear-Host; return }
        }
    }
}

# ------------------------------------------------------------------------------
# Workflow 1: Install
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Workflow 1 Helpers: Container Conflict & Inspection
# ------------------------------------------------------------------------------
function Test-ContainerConflict([string]$TargetDir) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
    if (-not (Test-ContainerExists "altr-stream")) { return $false }
    $cworkdir = Get-ContainerInspectField "altr-stream" '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
    if (-not $cworkdir -or ($cworkdir.Trim() -ne $TargetDir.Trim())) {
        return $true
    }
    return $false
}

function Show-ExistingContainerDetails([string]$TargetContainer = "altr-stream", [string]$ReturnLabel = "Back to Conflict Menu") {
    if (-not (Test-ContainerExists $TargetContainer)) {
        Invoke-GumStyle --foreground 196 "Container '$TargetContainer' does not exist."
        Invoke-GumChoose --cursor="❯ " $ReturnLabel
        return
    }

    $cid = Get-ContainerInspectField $TargetContainer '{{.Id}}'
    $cname = (Get-ContainerInspectField $TargetContainer '{{.Name}}') -replace '^/', ''
    $cstatus = Get-ContainerInspectField $TargetContainer '{{.State.Status}}'
    $chealth = Get-ContainerInspectField $TargetContainer '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
    $cimage = Get-ContainerInspectField $TargetContainer '{{.Config.Image}}'
    $ccreated = Get-ContainerInspectField $TargetContainer '{{.Created}}'
    $cports = Get-ContainerInspectField $TargetContainer '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}} {{end}}'
    $cproject = Get-ContainerInspectField $TargetContainer '{{index .Config.Labels "com.docker.compose.project"}}'
    $cworkdir = Get-ContainerInspectField $TargetContainer '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
    $cmounts = Get-ContainerInspectField $TargetContainer '{{range .Mounts}}{{.Name}}{{.Source}} -> {{.Destination}} ({{.Type}}) {{end}}'
    $cversion = Get-ContainerInspectField $TargetContainer '{{index .Config.Labels "org.opencontainers.image.version"}}'
    if (-not $cversion) {
        if ($cimage -match ':([^:]+)$') { $cversion = $matches[1] } else { $cversion = "Unknown" }
    }

    $classification = if ($cimage -match "altr-stream") { "✓ Identified as an Altr Stream container" } else { "⚠ Notice: This container does NOT appear to belong to Altr Stream." }

    Clear-Host
    Render-ScreenTop 24
    $pad = Get-LayoutPadding 68 24
    $leftPad = $pad[0]
    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 --align center --bold `
        "CONTAINER DETAILS" "" "$cname"

    $cidShort = if ($cid.Length -ge 12) { $cid.Substring(0, 12) } else { $cid }
    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
        "Container Attributes:" "" `
        "  Name:           $cname" `
        "  ID:             $cidShort ($cid)" `
        "  Status:         $cstatus" `
        "  Health State:   $chealth" `
        "  Image:          $cimage" `
        "  Version:        $cversion" `
        "  Created:        $ccreated" `
        "  Ports:          $(if ($cports) { $cports } else { 'None' })" `
        "  Compose Proj:   $(if ($cproject) { $cproject } else { 'None' })" `
        "  Working Dir:    $(if ($cworkdir) { $cworkdir } else { 'None' })" `
        "  Mounts:         $(if ($cmounts) { $cmounts } else { 'None' })" "" `
        "Classification:" `
        "  $classification"

    Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" $ReturnLabel
}

function Handle-RemoveExistingContainer([string]$TargetDir) {
    if (-not (Test-ContainerExists "altr-stream")) { return $true }
    $cid = Get-ContainerInspectField "altr-stream" '{{.Id}}'
    $cname = (Get-ContainerInspectField "altr-stream" '{{.Name}}') -replace '^/', ''
    $cidShort = if ($cid.Length -ge 12) { $cid.Substring(0, 12) } else { $cid }

    Render-ScreenTop 18
    $pad = Get-LayoutPadding 68 18
    $leftPad = $pad[0]
    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 `
        "⚠ EXISTING CONTAINER" "" `
        "A container named `"altr-stream`" already exists." "" `
        "Removing it may affect an existing Altr Stream" `
        "installation." "" `
        "Container: $cname" `
        "ID:        $cidShort"

    $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Proceed?" "Cancel" "Remove Container"
    if ($choice -ne "Remove Container") { return $false }

    Render-ScreenTop 18
    $pad = Get-LayoutPadding 68 18
    $leftPad = $pad[0]
    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 `
        "CONFIRM CONTAINER REMOVAL" "" `
        "Are you sure you want to remove container `"altr-stream`"?" "" `
        "This removes ONLY the container. Persistent data stored in" `
        "the named volume `"altr_stream_data`" will NOT be deleted."

    $confirm = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Are you sure?" "Cancel" "Confirm Removal"
    if ($confirm -ne "Confirm Removal") { return $false }

    if ($GumBin) {
        & $GumBin spin --spinner dot --title "Removing conflicting container altr-stream..." -- powershell -Command "docker rm -f altr-stream"
    } else {
        $null = Invoke-DockerCliSafe "rm -f altr-stream"
    }
    return $true
}

function Handle-UseExistingContainer([string]$TargetDir) {
    if (-not (Test-ContainerExists "altr-stream")) {
        Invoke-GumStyle --foreground 196 "Container 'altr-stream' no longer exists."
        Start-Sleep -Seconds 1
        return $false
    }

    $cimage = Get-ContainerInspectField "altr-stream" '{{.Config.Image}}'
    $cstatus = Get-ContainerInspectField "altr-stream" '{{.State.Status}}'
    $cworkdir = Get-ContainerInspectField "altr-stream" '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'

    if ($cimage -notmatch "altr-stream") {
        Render-ScreenTop 16
        $pad = Get-LayoutPadding 68 16
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 `
            "INCOMPATIBLE CONTAINER" "" `
            "The existing container does not appear to be an Altr Stream image." "" `
            "Image: $cimage"
        $sub = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" "Back to Conflict Menu" "View Container Details"
        if ($sub -eq "View Container Details") {
            Show-ExistingContainerDetails "altr-stream" "Back to Conflict Menu"
        }
        return $false
    }

    if ($cstatus -ne "running") {
        Render-ScreenTop 16
        $pad = Get-LayoutPadding 68 16
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 `
            "CONTAINER STOPPED" "" `
            "The existing Altr Stream container is currently stopped." "" `
            "Status: $cstatus"

        $startChoice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Would you like to start it now?" `
            "Start Container & Verify Health" "Back to Conflict Menu"
        if ($startChoice -ne "Start Container & Verify Health") { return $false }

        if ($GumBin) {
            & $GumBin spin --spinner dot --title "Starting container altr-stream..." -- powershell -Command "docker start altr-stream"
        } else {
            $null = Invoke-DockerCliSafe "start altr-stream"
        }
    }

    $healthy = $false
    for ($i = 1; $i -le 20; $i++) {
        try {
            $resp = Invoke-RestMethod -Uri "http://localhost:8000/api/v1/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($resp) { $healthy = $true; break }
        } catch {}
        Start-Sleep -Seconds 1
    }

    if (-not $healthy) {
        Render-ScreenTop 16
        $pad = Get-LayoutPadding 68 16
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 `
            "HEALTH CHECK FAILED" "" `
            "The existing container could not be verified." "" `
            "Health check at http://localhost:8000/api/v1/health did not respond."
        $sub = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" "Back to Conflict Menu" "View Container Details"
        if ($sub -eq "View Container Details") {
            Show-ExistingContainerDetails "altr-stream" "Back to Conflict Menu"
        }
        return $false
    }

    $versionStr = "v$Version"
    try {
        $resp = Invoke-RestMethod -Uri "http://localhost:8000/api/v1/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($resp -and $resp.version) { $versionStr = "v$($resp.version)" }
    } catch {}

    while ($true) {
        Render-ScreenTop 22
        $pad = Get-LayoutPadding 68 22
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border double --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
            "EXISTING ALTR STREAM FOUND"

        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
            "Container:" `
            "  altr-stream" "" `
            "Status:" `
            "  Running / Healthy" "" `
            "Version:" `
            "  $versionStr" "" `
            "Web Interface:" `
            "  http://localhost:8000" "" `
            "This existing installation can be used."

        $useChoice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" `
            "Use Existing Installation" "View Container Details" "Back"

        switch ($useChoice) {
            "Use Existing Installation" {
                $activeDir = if ($cworkdir -and (Test-Path (Join-Path $cworkdir "docker-compose.yml"))) { $cworkdir } else {
                    Write-RuntimeFiles $TargetDir
                    $TargetDir
                }
                Save-InstallDirectory $activeDir
                $env:ALTR_STREAM_HOME = $activeDir
                Show-InstallSuccessScreen $activeDir
                return $true
            }
            "View Container Details" {
                Show-ExistingContainerDetails "altr-stream" "Back"
            }
            default {
                return $false
            }
        }
    }
}

function Show-ConflictMenu([string]$TargetDir) {
    while ($true) {
        if (-not (Test-ContainerExists "altr-stream")) {
            Invoke-InstallWorkflow $TargetDir
            return
        }

        $cid = Get-ContainerInspectField "altr-stream" '{{.Id}}'
        $cname = (Get-ContainerInspectField "altr-stream" '{{.Name}}') -replace '^/', ''
        $cstatus = Get-ContainerInspectField "altr-stream" '{{.State.Status}}'
        $cimage = Get-ContainerInspectField "altr-stream" '{{.Config.Image}}'
        $cworkdir = Get-ContainerInspectField "altr-stream" '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
        $cidShort = if ($cid.Length -ge 12) { $cid.Substring(0, 12) } else { $cid }

        Render-ScreenTop 24
        $pad = Get-LayoutPadding 68 24
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 --align center --bold `
            "⚠ EXISTING CONTAINER DETECTED" "" `
            "A container named `"altr-stream`" already exists in Docker."

        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
            "Existing Container Info:" "" `
            "  Name:     $cname" `
            "  ID:       $cidShort" `
            "  Status:   $cstatus" `
            "  Image:    $cimage" `
            "  Path:     $(if ($cworkdir) { $cworkdir } else { 'Unknown / Not set' })"

        $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="What would you like to do?" `
            "Use Existing Altr Stream Container" `
            "Remove Existing Container" `
            "View Container Details" `
            "Retry Installation" `
            "Back to Main Menu" `
            "Exit"

        switch ($choice) {
            "Use Existing Altr Stream Container" {
                if (Handle-UseExistingContainer $TargetDir) { return }
            }
            "Remove Existing Container" {
                if (Handle-RemoveExistingContainer $TargetDir) {
                    Invoke-InstallWorkflow $TargetDir
                    return
                }
            }
            "View Container Details" {
                Show-ExistingContainerDetails "altr-stream" "Back to Conflict Menu"
            }
            "Retry Installation" {
                if (Test-ContainerConflict $TargetDir) {
                    Render-ScreenTop 14
                    $pad = Get-LayoutPadding 68 14
                    $leftPad = $pad[0]
                    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "0 2" --width 68 `
                        "⚠ Container `"altr-stream`" still exists." `
                        "Please resolve the conflict before retrying installation."
                    Start-Sleep -Milliseconds 1500
                } else {
                    Invoke-InstallWorkflow $TargetDir
                    return
                }
            }
            "Back to Main Menu" {
                return
            }
            default {
                Clear-Host
                Invoke-GumStyle --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
            }
        }
    }
}

# ------------------------------------------------------------------------------
# Workflow 1: Install
# ------------------------------------------------------------------------------
function Invoke-InstallWorkflow ([string]$target = "") {
    $targetDir = if ($target) { [System.IO.Path]::GetFullPath($target) } else { Get-InstallDirectory }

    $diag = Get-DockerDiagnostics
    if (-not $diag.EngineRunning -or -not $diag.ComposeAvailable) {
        if ($Action -ne "Menu") {
            $err = if ($diag.FailureReason) { $diag.FailureReason } else { "Docker Engine is required." }
            if ($diag.TechnicalError) {
                Write-Error "ERROR: $err`nTechnical Details: $($diag.TechnicalError)"
            } else {
                Write-Error "ERROR: $err"
            }
            exit 1
        }
        Show-DockerDiagnosticScreen $diag
        # Re-evaluate status: if engine was started and compose is ready, proceed; otherwise return to menu
        $diag = Get-DockerDiagnostics
        if (-not $diag.EngineRunning -or -not $diag.ComposeAvailable) {
            return
        }
    }

    $compose = $diag.ComposeCommand
    if (-not $compose) {
        $compose = Get-ComposeCommand
    }

    # Interactive Install prompt
    if ($GumBin -and ($Action -eq "Menu")) {
        $proceed = $false
        while (-not $proceed) {
            Render-ScreenTop 22
            $pad = Get-LayoutPadding 68 22
            $leftPad = $pad[0]
            Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 `
                "Install Altr Stream" "" `
                "Target Version:    v$Version" `
                "Installation Path: $targetDir" "" `
                "Prerequisites:" `
                "  ✓ Docker installed" `
                "  ✓ Docker daemon running" `
                "  ✓ Docker Compose available"

            $act = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Ready to proceed:" `
                "Install Altr Stream" "Change Installation Path" "Back to Main Menu"

            if ($act -eq "Install Altr Stream") {
                $proceed = $true
            } elseif ($act -eq "Change Installation Path") {
                $newPath = Invoke-GumInput --placeholder "Enter custom path" --value "$targetDir" --width 50
                if ($newPath -and $newPath.Trim() -ne "") {
                    $targetDir = [System.IO.Path]::GetFullPath($newPath.Trim())
                    Save-InstallDirectory $targetDir
                }
            } else {
                return
            }
        }
    }

    Save-InstallDirectory $targetDir
    $env:ALTR_STREAM_HOME = $targetDir

    # Pre-creation conflict detection
    if (Test-ContainerConflict $targetDir) {
        if ($GumBin -and ($Action -eq "Menu")) {
            Show-ConflictMenu $targetDir
            return
        } else {
            $cid = Get-ContainerInspectField "altr-stream" '{{.Id}}'
            $cname = (Get-ContainerInspectField "altr-stream" '{{.Name}}') -replace '^/', ''
            $cstatus = Get-ContainerInspectField "altr-stream" '{{.State.Status}}'
            $cimage = Get-ContainerInspectField "altr-stream" '{{.Config.Image}}'
            $cidShort = if ($cid.Length -ge 12) { $cid.Substring(0, 12) } else { $cid }
            Write-Error "ERROR: A container named 'altr-stream' already exists in Docker (ID: $cidShort, Status: $cstatus, Image: $cimage). Cannot proceed with installation while a conflicting container exists."
            exit 1
        }
    }

    $compose = Get-ComposeCommand
    $webUrl = Get-WebUrl $targetDir

    $failedStage = ""
    $failedReason = ""
    $failedTechnical = ""

    # Stage 1: Runtime configuration
    if ($GumBin -and ($Action -eq "Menu")) {
        & $GumBin spin --spinner dot --title "Preparing runtime configuration files..." -- Start-Sleep -Milliseconds 400
    }
    try {
        Write-RuntimeFiles $targetDir
    }
    catch {
        $failedStage = "Preparing configuration"
        $failedReason = "Failed to write configuration files into $targetDir"
        $failedTechnical = $_.Exception.Message
    }

    # Stage 2: Persistent storage volume
    if (-not $failedStage) {
        if ($GumBin -and ($Action -eq "Menu")) {
            & $GumBin spin --spinner dot --title "Preparing persistent storage volume (altr_stream_data)..." -- Start-Sleep -Milliseconds 300
        }
        $volRes = Invoke-DockerCliSafe "volume create altr_stream_data"
        if (-not $volRes.Success) {
            $failedStage = "Preparing storage volume"
            $failedReason = "Failed to create named Docker volume 'altr_stream_data'."
            $failedTechnical = $volRes.Error
        }
    }

    # Stage 3: Pulling image
    if (-not $failedStage) {
        $dockerPullLog = Join-Path $targetDir ".docker_pull.log"
        Remove-Item $dockerPullLog -Force -ErrorAction SilentlyContinue

        $pullExit = 0
        if ($GumBin -and ($Action -eq "Menu")) {
            & $GumBin spin --spinner dot --title "Downloading / pulling Altr Stream image ($AltrImage)..." -- `
                powershell -NoProfile -ExecutionPolicy Bypass -Command "$compose -f `"$targetDir\docker-compose.yml`" pull 2>&1 | Out-File -Encoding UTF8 -FilePath `"$dockerPullLog`""
            $pullExit = $LASTEXITCODE
        } else {
            powershell -NoProfile -ExecutionPolicy Bypass -Command "$compose -f `"$targetDir\docker-compose.yml`" pull 2>&1 | Out-File -Encoding UTF8 -FilePath `"$dockerPullLog`""
            $pullExit = $LASTEXITCODE
        }

        if ($pullExit -ne 0) {
            $imgRes = Invoke-DockerCliSafe "images -q $AltrImage"
            $localImg = $imgRes.Output
            if (-not $localImg) {
                $failedStage = "Pulling Altr Stream image"
                $pTech = if (Test-Path $dockerPullLog) { (Get-Content $dockerPullLog -Raw).Trim() } else { "" }
                $failedTechnical = $pTech
                if ($pTech -match "manifest.*not found") {
                    $failedReason = "Image $AltrImage not found on remote registry."
                } elseif ($pTech -match "network|timeout|connection refused|dial tcp") {
                    $failedReason = "Network error while downloading image $AltrImage."
                } elseif ($pTech) {
                    $failedReason = ($pTech -split "`r?`n")[0].Trim()
                } else {
                    $failedReason = "Failed to pull image $AltrImage."
                }
            }
        }
    }

    # Stage 4: Starting container
    if (-not $failedStage) {
        $startFailed = $false
        $dockerStartLog = Join-Path $targetDir ".docker_start.log"
        Remove-Item $dockerStartLog -Force -ErrorAction SilentlyContinue

        if ($GumBin -and ($Action -eq "Menu")) {
            & $GumBin spin --spinner dot --title "Creating & starting Altr Stream container..." -- `
                powershell -NoProfile -ExecutionPolicy Bypass -Command "$compose -f `"$targetDir\docker-compose.yml`" up -d 2>&1 | Out-File -Encoding UTF8 -FilePath `"$dockerStartLog`""
            if ($LASTEXITCODE -ne 0) { $startFailed = $true }
        } else {
            powershell -NoProfile -ExecutionPolicy Bypass -Command "$compose -f `"$targetDir\docker-compose.yml`" up -d 2>&1 | Out-File -Encoding UTF8 -FilePath `"$dockerStartLog`""
            if ($LASTEXITCODE -ne 0) { $startFailed = $true }
        }

        if ($startFailed) {
            $failedStage = "Starting Altr Stream container"
            if (Test-Path $dockerStartLog) {
                $failedTechnical = (Get-Content $dockerStartLog -Raw).Trim()
            }
            if ($failedTechnical -match "Conflict.*container name.*already in use") {
                $failedReason = "Container name 'altr-stream' is already in use."
            } elseif ($failedTechnical -match "port is already allocated|bind: address already in use") {
                $failedReason = "Port 8000 is already in use by another application."
            } elseif ($failedTechnical) {
                $firstLine = ($failedTechnical -split "`n")[0].Trim()
                $failedReason = if ($firstLine) { $firstLine } else { "docker compose up -d encountered an error." }
            } else {
                $failedReason = "docker compose up -d encountered an error."
            }
        }
    }

    # Stage 5: Polling Healthcheck
    if (-not $failedStage) {
        $maxAttempts = 30
        $healthy = $false
        if ($GumBin -and ($Action -eq "Menu")) {
            & $GumBin spin --spinner dot --title "Waiting for container health check at $webUrl..." -- powershell -Command "
                `$h = `$false
                for (`$i = 1; `$i -le 30; `$i++) {
                    try {
                        `$r = Invoke-RestMethod -Uri '$webUrl/api/v1/health' -TimeoutSec 2 -ErrorAction SilentlyContinue
                        if (`$r) { `$h = `$true; break }
                    } catch {}
                    Start-Sleep -Seconds 1
                }
                if (-not `$h) { exit 1 } else { exit 0 }
            "
            if ($LASTEXITCODE -eq 0) { $healthy = $true }
        } else {
            for ($i = 1; $i -le $maxAttempts; $i++) {
                try {
                    $resp = Invoke-RestMethod -Uri "$webUrl/api/v1/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
                    if ($resp) { $healthy = $true; break }
                } catch {}
                Start-Sleep -Seconds 1
            }
        }

        if (-not $healthy) {
            $failedStage = "Waiting for health check"
            $failedReason = "Container health check timed out after $maxAttempts seconds at $webUrl"
        }
    }

    # Verification and screen transition
    $verified = $false
    if (-not $failedStage) {
        $verified = Test-InstallationHealth $targetDir
        if (-not $verified) {
            $failedStage = "Installation verification"
            $failedReason = "Container verification failed: container is not healthy or responsive at $webUrl."
        }
    }

    if ($verified) {
        if ($GumBin -and ($Action -eq "Menu")) {
            Show-InstallSuccessScreen $targetDir
        } else {
            Write-Host "Altr Stream is installed and running at $webUrl" -ForegroundColor Green
        }
    } else {
        if ($GumBin -and ($Action -eq "Menu")) {
            $errStage = if ($failedStage) { $failedStage } else { "Health Verification" }
            $errReason = if ($failedReason) { $failedReason } else { "Altr Stream installation failed." }
            Show-InstallFailureScreen $targetDir $errStage $errReason $failedTechnical
        } else {
            Write-Error "Installation verification failed at stage: $failedStage. Reason: $failedReason. Technical: $failedTechnical"
            exit 1
        }
    }
}

function Show-InstallSuccessScreen([string]$TargetDir) {
    $webUrl = Get-WebUrl $TargetDir

    while ($true) {
        Render-ScreenTop 24
        $pad = Get-LayoutPadding 68 24
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border double --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
            "✓ INSTALLATION COMPLETE" "" `
            "ALTR STREAM" "v$Version"

        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
            "Installation Summary:" "" `
            "  ✓ Docker Engine       Running" `
            "  ✓ Altr Stream         Running" `
            "  ✓ Container           Healthy" `
            "  ✓ Version             v$Version" `
            "  ✓ Installation Path   $TargetDir" `
            "  ✓ Persistent Data     Enabled (altr_stream_data)" `
            "  ✓ Web Interface       $webUrl"

        Invoke-GumStyle --margin "0 0 0 $leftPad" --foreground 245 "Altr Stream is ready to use."

        $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="What would you like to do?" `
            "Launch Altr Stream" "Open Web Interface" "Installation Status" "Back to Main Menu" "Exit"

        switch ($choice) {
            { $_ -in "Launch Altr Stream", "Open Web Interface" } {
                Invoke-LaunchBrowser $webUrl
                Show-RunningScreen $TargetDir $webUrl
                return
            }
            "Installation Status" {
                Invoke-StatusWorkflow $TargetDir
            }
            "Back to Main Menu" {
                return
            }
            default {
                Clear-Host
                Invoke-GumStyle --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
            }
        }
    }
}

function Show-RunningScreen([string]$TargetDir, [string]$WebUrl) {
    while ($true) {
        Render-ScreenTop 20
        $pad = Get-LayoutPadding 68 20
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border double --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
            "✓ ALTR STREAM IS RUNNING" "" `
            "Web Interface:" `
            "$WebUrl" "" `
            "The interface has been opened in your default browser."

        $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="What would you like to do?" `
            "Open Altr Stream Again" "Installation Status" "Back to Main Menu" "Exit"

        switch ($choice) {
            "Open Altr Stream Again" {
                Invoke-LaunchBrowser $WebUrl
            }
            "Installation Status" {
                Invoke-StatusWorkflow $TargetDir
            }
            "Back to Main Menu" {
                return
            }
            default {
                Clear-Host
                Invoke-GumStyle --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
            }
        }
    }
}

function Show-InstallFailureScreen([string]$TargetDir, [string]$Stage, [string]$Reason, [string]$Technical = "") {
    $compose = Get-ComposeCommand

    while ($true) {
        Render-ScreenTop 24
        $pad = Get-LayoutPadding 68 24
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 --align center --bold `
            "✕ INSTALLATION FAILED" "" `
            "Altr Stream could not be started successfully."

        $dockerStat = Get-DockerStatusText
        $altrStat = Get-AltrStatusText $TargetDir

        $diag = @(
            "Failure Diagnostics:", ""
            "  Stage:          $Stage"
            "  Reason:         $Reason"
        )
        if ($Technical) {
            $tFormatted = Format-TechnicalLines $Technical 4 58
            if ($tFormatted.Count -gt 0) {
                $diag += "  Technical:"
                foreach ($tl in $tFormatted) { $diag += "  $tl" }
            }
        }
        $diag += @(
            "", "Current State:",
            "  Docker Engine:  $dockerStat",
            "  Container:      $altrStat",
            "  Path:           $TargetDir"
        )

        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 @diag

        $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="What would you like to do?" `
            "Retry Installation" "View Installation Status" "View Container Logs" "Back to Main Menu" "Exit"

        switch ($choice) {
            "Retry Installation" {
                Invoke-InstallWorkflow $TargetDir
                return
            }
            "View Installation Status" {
                Invoke-StatusWorkflow $TargetDir
            }
            "View Container Logs" {
                $hasContainer = $false
                if ($compose -and (Test-Path (Join-Path $TargetDir "docker-compose.yml"))) {
                    $cidProj = (Invoke-Expression "$compose -f `"$TargetDir\docker-compose.yml`" ps -q altr-stream" 2>$null)
                    if ($cidProj) { $hasContainer = $true }
                }

                if (-not $hasContainer -or ($Stage -eq "Starting Altr Stream container")) {
                    Render-ScreenTop 20
                    $pad = Get-LayoutPadding 68 20
                    $leftPad = $pad[0]
                    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 --align center --bold `
                        "CONTAINER LOGS"

                    $cidConf = Get-ContainerInspectField "altr-stream" '{{.Id}}'
                    $cnameConf = (Get-ContainerInspectField "altr-stream" '{{.Name}}') -replace '^/', ''
                    $cstateConf = Get-ContainerInspectField "altr-stream" '{{.State.Status}}'
                    $cidConfShort = if ($cidConf.Length -ge 12) { $cidConf.Substring(0, 12) } else { $cidConf }

                    $logLines = @(
                        "No logs are available for the new container because Docker failed",
                        "before the container could be created.", "",
                        "Docker reported:"
                    )
                    $tFormatted = Format-TechnicalLines $(if ($Technical) { $Technical } else { $Reason }) 4 58
                    foreach ($tl in $tFormatted) { $logLines += "  $tl" }
                    if ($cidConf) {
                        $logLines += @(
                            "",
                            "Conflicting container:",
                            "  Name:  $cnameConf",
                            "  ID:    $cidConfShort",
                            "  State: $cstateConf"
                        )
                    }

                    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 @logLines

                    $logAction = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" "View Container Details" "Back to Failure Menu"
                    if ($logAction -eq "View Container Details") {
                        Show-ExistingContainerDetails "altr-stream" "Back to Failure Menu"
                    }
                }
                else {
                    Clear-Host
                    Write-Host "--- Container Logs (last 30 lines) ---" -ForegroundColor Cyan
                    Invoke-Expression "$compose -f `"$TargetDir\docker-compose.yml`" logs --tail 30 altr-stream"
                    Write-Host "--------------------------------------" -ForegroundColor Cyan
                    Invoke-GumChoose --cursor="❯ " "Return to Failure Menu"
                }
            }
            "Back to Main Menu" {
                return
            }
            default {
                Clear-Host
                Invoke-GumStyle --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
            }
        }
    }
}

# ------------------------------------------------------------------------------
# Workflow 2: Uninstall
# ------------------------------------------------------------------------------
function Invoke-UninstallWorkflow ([string]$target = "") {
    $targetDir = if ($target) { [System.IO.Path]::GetFullPath($target) } else { Get-InstallDirectory }

    if (-not (Test-Path (Join-Path $targetDir "docker-compose.yml"))) {
        Write-Host "No active Altr Stream installation detected at $targetDir" -ForegroundColor Yellow
        if ($GumBin -and ($Action -eq "Menu")) { Invoke-GumConfirm "Press Enter to return..." }
        return
    }

    $compose = Get-ComposeCommand
    $keepData = $true

    if ($GumBin -and ($Action -eq "Menu")) {
        Render-ScreenTop 20
        $pad = Get-LayoutPadding 68 20
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 `
            "Uninstall Altr Stream" "" `
            "Installed Version: v$Version" `
            "Location:          $targetDir"

        $dataChoice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="What should happen to your application data?" `
            "Keep application data (Recommended - preserves database, models, data sources)" `
            "Delete application data permanently (Destroys named volume altr_stream_data)" `
            "Cancel"

        switch -Wildcard ($dataChoice) {
            "Keep application data*"   { $keepData = $true }
            "Delete application data*" { $keepData = $false }
            default                    { return }
        }
    }

    $deleteConfirmed = $false
    if (-not $keepData) {
        if ($GumBin -and ($Action -eq "Menu")) {
            Render-ScreenTop 22
            $pad = Get-LayoutPadding 68 22
            $leftPad = $pad[0]
            Invoke-GumStyle --margin "0 0 0 $leftPad" --border double --border-foreground 196 --padding "1 2" --width 68 --bold `
                "⚠ DESTRUCTIVE DATA DELETION" "" `
                "All application state, connections, and volume 'altr_stream_data' will be ERASED." `
                "This action cannot be undone." "" `
                "To confirm permanent destruction, type:" `
                "DELETE ALTR STREAM DATA"

            $confStr = Invoke-GumInput --placeholder "Type confirmation here" --prompt "Confirmation: " --width 50
            if ($confStr -eq "DELETE ALTR STREAM DATA") {
                $deleteConfirmed = $true
            }
            else {
                Invoke-GumStyle --foreground 214 "Confirmation text did not match. Application data will be preserved."
            }
        }
        else {
            $confStr = Read-Host "To confirm destructive deletion, type: DELETE ALTR STREAM DATA"
            if ($confStr -eq "DELETE ALTR STREAM DATA") {
                $deleteConfirmed = $true
            }
            else {
                Write-Host "Confirmation text did not match. Application data will be preserved." -ForegroundColor Yellow
            }
        }
    }

    if ($compose) {
        Invoke-Expression "$compose -f `"$targetDir\docker-compose.yml`" down" 2>$null
    }

    Remove-Item -Path (Join-Path $targetDir "docker-compose.yml") -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $targetDir ".env") -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $targetDir "data\updates") -Recurse -Force -ErrorAction SilentlyContinue

    if ($deleteConfirmed) {
        $null = Invoke-DockerCliSafe "volume rm -f altr_stream_data"
    }

    $volStat = if ($deleteConfirmed) { "DELETED" } else { "PRESERVED" }
    if ($GumBin -and ($Action -eq "Menu")) {
        Render-ScreenTop 20
        $pad = Get-LayoutPadding 68 20
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
            "✓ UNINSTALLED" "" `
            "Altr Stream deployment files removed." `
            "Named Volume 'altr_stream_data': $volStat"
        Invoke-GumConfirm "Press Enter to return..."
    }
    else {
        Write-Host "Uninstall complete. Volume: $volStat" -ForegroundColor Green
    }
}

# ------------------------------------------------------------------------------
# Workflow 3: Repair
# ------------------------------------------------------------------------------
function Invoke-RepairWorkflow ([string]$target = "") {
    $targetDir = if ($target) { [System.IO.Path]::GetFullPath($target) } else { Get-InstallDirectory }
    $compose = Get-ComposeCommand
    $webUrl = Get-WebUrl $targetDir

    $hasDir = Test-Path $targetDir
    $hasCompose = Test-Path (Join-Path $targetDir "docker-compose.yml")
    $diag = Get-DockerDiagnostics
    $daemonOk = ($diag.EngineRunning -and $diag.ComposeAvailable)
    $containerOk = $false
    $healthOk = $false

    if ($compose -and $hasCompose) {
        $psOut = (Invoke-Expression "$compose -f `"$targetDir\docker-compose.yml`" ps" 2>$null) -join " "
        if ($psOut -match "altr-stream") { $containerOk = $true }
    }
    try {
        $hResp = Invoke-RestMethod -Uri "$webUrl/api/v1/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($hResp) { $healthOk = $true }
    }
    catch {
        try {
            $hResp = Invoke-RestMethod -Uri "$webUrl/api/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($hResp) { $healthOk = $true }
        } catch {}
    }

    if ($GumBin -and ($Action -eq "Menu")) {
        Render-ScreenTop 24
        $pad = Get-LayoutPadding 68 24
        $leftPad = $pad[0]

        $engineStatusLabel = if ($daemonOk) { '✓ Docker engine responsive' } else { "✗ Docker daemon unreachable ($($diag.StatusText))" }
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 `
            "Repair Altr Stream" "" `
            "Diagnostic Checks:" `
            "  $(if ($hasDir) { '✓ Directory exists' } else { '✗ Directory missing' })" `
            "  $(if ($hasCompose) { '✓ docker-compose.yml present' } else { '✗ docker-compose.yml missing' })" `
            "  $engineStatusLabel" `
            "  $(if ($containerOk) { '✓ Container active' } else { '⚠ Container stopped or missing' })" `
            "  $(if ($healthOk) { '✓ Healthcheck responding' } else { '✗ Healthcheck offline' })" "" `
            "Recommended Action:" `
            "Repair will restore configuration files, inspect the container," `
            "and safely recreate or recover it. Persistent data is preserved."

        $proceed = Invoke-GumConfirm "Proceed with Repair?"
        if (-not $proceed) { return }
    } else {
        if (-not $daemonOk) {
            Write-Error "ERROR: Docker Engine is unreachable ($($diag.StatusText))."
            exit 1
        }
    }

    $failedStage = ""
    $failedReason = ""
    $failedTechnical = ""

    # Stage 1: Restore configuration & runtime files
    if ($GumBin -and ($Action -eq "Menu")) {
        & $GumBin spin --spinner dot --title "Restoring configuration files..." -- powershell -Command "Start-Sleep -Milliseconds 400"
    }
    try {
        Write-RuntimeFiles $targetDir
    }
    catch {
        $failedStage = "Restoring configuration files"
        $failedReason = "Failed to write configuration files into $targetDir"
        $failedTechnical = $_.Exception.Message
    }
    $volRes = Invoke-DockerCliSafe "volume create altr_stream_data"
    Save-InstallDirectory $targetDir

    # Stage 2: Inspect existing "altr-stream" container lifecycle
    $existingExists = $false
    $existingStatus = ""
    $existingImage = ""
    $existingMounts = ""
    $existingCompatible = $false
    $existingHealthy = $false
    $existingHasVolume = $false
    $needsReplacement = $true

    if (-not $failedStage -and (Get-Command docker -ErrorAction SilentlyContinue)) {
        if (Test-ContainerExists "altr-stream") {
            $existingExists = $true
            $existingStatus = Get-ContainerInspectField "altr-stream" '{{.State.Status}}'
            $existingImage = Get-ContainerInspectField "altr-stream" '{{.Config.Image}}'
            $existingMounts = Get-ContainerInspectField "altr-stream" '{{range .Mounts}}{{.Name}} {{end}}'

            if ($existingImage -match "altr-stream") { $existingCompatible = $true }
            if ($existingMounts -match "altr_stream_data") { $existingHasVolume = $true }
            try {
                $hResp = Invoke-RestMethod -Uri "$webUrl/api/v1/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
                if ($hResp) { $existingHealthy = $true }
            } catch {
                try {
                    $hResp = Invoke-RestMethod -Uri "$webUrl/api/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
                    if ($hResp) { $existingHealthy = $true }
                } catch {}
            }

            if ($existingCompatible -and $existingHealthy -and $existingHasVolume -and ($existingStatus -eq "running")) {
                $needsReplacement = $false
            }
        }
    }

    # Stage 3: Replacement / Recreate if needed
    if (-not $failedStage -and $needsReplacement -and $compose) {
        if ($GumBin -and ($Action -eq "Menu")) {
            & $GumBin spin --spinner dot --title "Pulling container image ($AltrImage)..." -- powershell -Command "$compose -f `"$targetDir\docker-compose.yml`" pull"
        }
        else {
            Invoke-Expression "$compose -f `"$targetDir\docker-compose.yml`" pull" 2>$null
        }

        # Safe removal of existing container to eliminate name collisions
        if ($existingExists) {
            if ($GumBin -and ($Action -eq "Menu")) {
                & $GumBin spin --spinner dot --title "Preparing canonical container altr-stream..." -- powershell -Command "docker stop altr-stream; docker rm altr-stream"
            } else {
                $null = Invoke-DockerCliSafe "stop altr-stream"
                $null = Invoke-DockerCliSafe "rm altr-stream"
            }
        }

        $recreateFailed = $false
        $logPath = Join-Path $targetDir ".docker_start.log"
        if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }

        if ($GumBin -and ($Action -eq "Menu")) {
            & $GumBin spin --spinner dot --title "Recreating container..." -- powershell -NoProfile -Command "$compose -f `\"$targetDir\docker-compose.yml`\" up -d *>`\"$logPath`\""
            if ($LASTEXITCODE -ne 0) { $recreateFailed = $true }
        }
        else {
            Invoke-Expression "$compose -f `"$targetDir\docker-compose.yml`" up -d *>`\"$logPath`\""
            if ($LASTEXITCODE -ne 0) { $recreateFailed = $true }
        }

        if ($recreateFailed) {
            $failedStage = "Recreating container"
            $failedReason = "Docker failed to recreate the Altr Stream container"
            if (Test-Path $logPath) {
                $rawLogs = Get-Content -Path $logPath -Tail 5 -ErrorAction SilentlyContinue
                if ($rawLogs) { $failedTechnical = ($rawLogs -join " ") }
            }
        }
    }

    # Stage 4: Health Verification
    if (-not $failedStage) {
        $healthy = $false
        for ($i = 1; $i -le 25; $i++) {
            try {
                $resp = Invoke-RestMethod -Uri "$webUrl/api/v1/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
                if ($resp) { $healthy = $true; break }
            }
            catch {}
            Start-Sleep -Seconds 1
        }
        if (-not $healthy) {
            $failedStage = "Waiting for Altr Stream health check"
            $failedReason = "Health check timed out after waiting for $webUrl/api/v1/health"
        }
    }

    # Strict Verification
    if (-not $failedStage -and (Test-InstallationHealth $targetDir)) {
        if ($GumBin -and ($Action -eq "Menu")) {
            Show-RepairSuccessScreen $targetDir
        }
        else {
            Write-Host "Altr Stream repair completed successfully and verified at $webUrl" -ForegroundColor Green
        }
    }
    else {
        if ($GumBin -and ($Action -eq "Menu")) {
            $errStage = if ($failedStage) { $failedStage } else { "Health Verification" }
            $errReason = if ($failedReason) { $failedReason } else { "Altr Stream health verification failed after repair" }
            Show-RepairFailureScreen $targetDir $errStage $errReason $failedTechnical
        }
        else {
            Write-Error "Repair failed at stage: $failedStage. Reason: $failedReason. Technical: $failedTechnical"
            exit 1
        }
    }
}

function Show-RepairSuccessScreen([string]$TargetDir) {
    $webUrl = Get-WebUrl $TargetDir

    while ($true) {
        Render-ScreenTop 24
        $pad = Get-LayoutPadding 68 24
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border double --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
            "✓ REPAIR COMPLETE" "" `
            "ALTR STREAM" "v$Version"

        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
            "Repair Summary:" "" `
            "  ✓ Configuration restored" `
            "  ✓ Persistent data preserved" `
            "  ✓ Container recreated" `
            "  ✓ Container running" `
            "  ✓ Container healthy" `
            "  ✓ Version verified" `
            "  ✓ Web Interface: $webUrl"

        $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="What would you like to do?" `
            "Launch Altr Stream" "Open Web Interface" "Installation Status" "Back to Main Menu" "Exit"

        switch ($choice) {
            { $_ -in "Launch Altr Stream", "Open Web Interface" } {
                Invoke-LaunchBrowser $webUrl
                Show-RunningScreen $TargetDir $webUrl
                return
            }
            "Installation Status" {
                Invoke-StatusWorkflow $TargetDir
            }
            "Back to Main Menu" {
                return
            }
            default {
                Clear-Host
                Invoke-GumStyle --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
            }
        }
    }
}

function Show-RepairFailureScreen([string]$TargetDir, [string]$Stage, [string]$Reason, [string]$Technical = "") {
    $compose = Get-ComposeCommand

    while ($true) {
        Render-ScreenTop 24
        $pad = Get-LayoutPadding 68 24
        $leftPad = $pad[0]
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 --align center --bold `
            "✕ REPAIR FAILED"

        $dockerStat = Get-DockerStatusText
        $altrStat = Get-AltrStatusText $TargetDir

        $lines = @(
            "Repair failed during:",
            "  $Stage",
            "",
            "Reason:",
            "  $Reason"
        )
        if ($Technical) {
            $lines += ""
            $lines += "Technical Details:"
            $tFormatted = Format-TechnicalLines $Technical 4 58
            foreach ($tl in $tFormatted) { $lines += "  $tl" }
        }
        $lines += ""
        $lines += "Current State:"
        $lines += "  Docker Engine: $dockerStat"
        $lines += "  Container:     $altrStat"
        $lines += "  Path:          $TargetDir"

        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 @lines

        $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="What would you like to do?" `
            "Retry Repair" "View Installation Status" "View Container Logs" "Back to Main Menu" "Exit"

        switch ($choice) {
            "Retry Repair" {
                Invoke-RepairWorkflow $TargetDir
                return
            }
            "View Installation Status" {
                Invoke-StatusWorkflow $TargetDir
            }
            "View Container Logs" {
                $hasContainer = $false
                if ($compose -and (Test-Path (Join-Path $TargetDir "docker-compose.yml"))) {
                    $cidProj = (Invoke-Expression "$compose -f `"$TargetDir\docker-compose.yml`" ps -q altr-stream" 2>$null)
                    if ($cidProj) { $hasContainer = $true }
                }

                if (-not $hasContainer -or ($Stage -eq "Recreating container")) {
                    Render-ScreenTop 20
                    $pad = Get-LayoutPadding 68 20
                    $leftPad = $pad[0]
                    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 --align center --bold `
                        "CONTAINER LOGS"

                    $repairLogLines = @(
                        "No logs are available for the recreated container because Docker",
                        "encountered an error during container creation/startup.", "",
                        "Docker reported:"
                    )
                    $tFormatted = Format-TechnicalLines $(if ($Technical) { $Technical } else { $Reason }) 4 58
                    foreach ($tl in $tFormatted) { $repairLogLines += "  $tl" }
                    Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 @repairLogLines

                    $logAction = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Actions:" `
                        "Back to Repair Menu" "Back to Main Menu" "Exit"
                    if ($logAction -eq "Back to Main Menu") { return }
                    if ($logAction -eq "Exit") { exit 0 }
                }
                else {
                    Clear-Host
                    Write-Host "--- Container Logs (tail 50 lines) ---" -ForegroundColor Cyan
                    Invoke-Expression "$compose -f `"$TargetDir\docker-compose.yml`" logs --tail 50 altr-stream"
                    Write-Host "--------------------------------------" -ForegroundColor Cyan
                    Invoke-GumConfirm "Press Enter to return..."
                }
            }
            "Back to Main Menu" {
                return
            }
            default {
                Clear-Host
                Invoke-GumStyle --foreground 245 "Exited Altr Stream Setup Utility."
                exit 0
            }
        }
    }
}

# ------------------------------------------------------------------------------
# Workflow 4: Status
# ------------------------------------------------------------------------------
function Invoke-StatusWorkflow ([string]$target = "") {
    $targetDir = if ($target) { [System.IO.Path]::GetFullPath($target) } else { Get-InstallDirectory }
    $diag = Get-DockerDiagnostics
    $dockerStat = $diag.StatusText
    $altrStat = Get-AltrStatusText $targetDir
    $webPort = Get-WebPort $targetDir
    $webUrl = Get-WebUrl $targetDir

    if ($GumBin -and ($Action -eq "Menu")) {
        Render-ScreenTop 22
        $pad = Get-LayoutPadding 68 22
        $leftPad = $pad[0]
        $statusLines = @(
            "Altr Stream Installation Status", "",
            "Installation:",
            "  Configured Version: v$Version",
            "  Target Directory:   $targetDir",
            "  Canonical Image:    $AltrImage", "",
            "Runtime & Container:",
            "  Docker Engine:      $dockerStat",
            "  Altr Container:     $altrStat",
            "  Web Port:           $webPort",
            "  Web Interface:      $webUrl",
            "  Named Volume:       altr_stream_data"
        )
        if ($diag.ActionHint -and $diag.StatusText -ne "Ready") {
            $statusLines += ""
            $statusLines += "Docker Action:"
            $statusLines += "  $($diag.ActionHint)"
        }
        Invoke-GumStyle --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 @statusLines
        Invoke-GumChoose --cursor="❯ " --header="" "Return" | Out-Null
    }
    else {
        Write-Host "Altr Stream Installation Status: Configured Version v$Version at $targetDir"
        Write-Host "Docker: $dockerStat | Container: $altrStat | Web Interface: $webUrl"
        if ($diag.ActionHint -and $diag.StatusText -ne "Ready") {
            Write-Host "Docker Action Hint: $($diag.ActionHint)"
        }
    }
}

# ------------------------------------------------------------------------------
# Main Execution Dispatch
# ------------------------------------------------------------------------------
switch ($Action) {
    "Install"   { Invoke-InstallWorkflow $InstallPath }
    "Uninstall" { Invoke-UninstallWorkflow $InstallPath }
    "Repair"    { Invoke-RepairWorkflow $InstallPath }
    "Status"    { Invoke-StatusWorkflow $InstallPath }
    "Menu" {
        if (Resolve-Gum) {
            Show-MainMenu
        }
        else {
            Write-Host "Notice: Gum interactive UI could not be initialized. Defaulting to Install workflow." -ForegroundColor Yellow
            Invoke-InstallWorkflow $InstallPath
        }
    }
}
