<#
.SYNOPSIS
    Altr Stream — Windows Setup Utility
.DESCRIPTION
    Application-grade Terminal Setup Utility powered by Charmbracelet Gum for Windows:
    Install, Uninstall, Repair, and Status.
.PARAMETER Action
    Optional direct action: Install, Uninstall, Repair, Status, or Menu (default).
.PARAMETER Version
    The version of Altr Stream. Defaults to 0.13.7-alpha.
.PARAMETER InstallPath
    Target directory for Altr Stream runtime and data. Defaults to $HOME\.altr-stream.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Altr-Stream_Windows_Installer.ps1
#>

[CmdletBinding()]
param (
    [ValidateSet("Menu", "Install", "Uninstall", "Repair", "Status")]
    [string]$Action = "Menu",
    [string]$Version = "0.13.7-alpha",
    [string]$InstallPath = ""
)

$ErrorActionPreference = "Stop"

$AltrImage = "ghcr.io/helloaltr/altr-stream:$Version"
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
    # 1. Bundled next to script (e.g. within release zip: Altr-Stream_Windows_Installer.ps1 + bin\gum.exe)
    if ($PSScriptRoot) {
        $bundledGum = Join-Path $PSScriptRoot "bin\gum.exe"
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
            & $GumBin style --margin "0 0 0 $leftPad" --border double --border-foreground 214 --padding "1 2" --width $cardW --align center --bold `
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

function Invoke-GumChoose {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    if (-not $GumBin) { return $null }
    $selPad = Get-ViewportSelPad
    & $GumBin choose --padding="0 0 0 $selPad" @Args
}

function Invoke-GumConfirm {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    if (-not $GumBin) { return $null }
    $selPad = Get-ViewportSelPad
    & $GumBin confirm --padding="0 0 0 $selPad" @Args
}

function Invoke-GumInput {
    param([Parameter(ValueFromRemainingArguments = $true)]$Args)
    if (-not $GumBin) { return $null }
    $selPad = Get-ViewportSelPad
    & $GumBin input --padding="0 0 0 $selPad" @Args
}


# ------------------------------------------------------------------------------
# Docker & Compose Checks
# ------------------------------------------------------------------------------
function Test-DockerEngine {
    try {
        $null = docker info 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Get-ComposeCommand {
    try {
        $null = docker compose version 2>$null
        if ($LASTEXITCODE -eq 0) { return "docker compose" }
    }
    catch {}

    try {
        $null = docker-compose version 2>$null
        if ($LASTEXITCODE -eq 0) { return "docker-compose" }
    }
    catch {}

    return ""
}

function Get-DockerStatusText {
    $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
    if (-not $dockerCmd) { return "Missing" }
    if (-not (Test-DockerEngine)) { return "Stopped" }
    $compose = Get-ComposeCommand
    if (-not $compose) { return "No Compose" }
    return "Running"
}

function Get-WebPort([string]$dir = "") {
    if (-not $dir) { $dir = Get-InstallDirectory }
    $envFile = Join-Path $dir ".env"
    if (Test-Path $envFile) {
        $line = Get-Content $envFile | Where-Object { $_ -match "^ALTR_STREAM_PORT=" } | Select-Object -First 1
        if ($line) {
            return ($line -split "=")[1].Trim(" `"'`r`n")
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

    try {
        $st = docker inspect -f '{{.State.Status}}' altr-stream 2>$null
        if ($st -eq "running") { return "Running" }
        if ($st) { return "Stopped" }
    }
    catch {}

    return "Stopped"
}

function Test-InstallationHealth([string]$TargetDir) {
    if (-not (Test-Path $TargetDir)) { return $false }
    if (-not (Test-Path (Join-Path $TargetDir "docker-compose.yml"))) { return $false }
    if (-not (Test-Path (Join-Path $TargetDir ".env"))) { return $false }

    $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
    if (-not $dockerCmd) { return $false }

    try {
        $cstatus = docker inspect -f '{{.State.Status}}' altr-stream 2>$null
        if ($cstatus -ne "running") { return $false }

        $cimage = docker inspect -f '{{.Config.Image}}' altr-stream 2>$null
        if ($cimage -notmatch "altr-stream") { return $false }

        $cmounts = docker inspect -f '{{range .Mounts}}{{.Name}} {{end}}' altr-stream 2>$null
        if ($cmounts -notmatch "altr_stream_data") { return $false }
    }
    catch {
        return $false
    }

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

    $composeContent = @"
services:
  altr-stream:
    image: ghcr.io/helloaltr/altr-stream:$Version
    container_name: altr-stream
    restart: unless-stopped
    ports:
      - "`$"{ALTR_STREAM_PORT:-8000}:8000"
    volumes:
      - altr_stream_data:/app/data
      - ./data/updates:/app/data/updates
    environment:
      - ALTR_STREAM_HOST=0.0.0.0
      - ALTR_STREAM_PORT=8000
      - ALTR_STREAM_DATA_DIR=/app/data
      - ALTR_STREAM_DEBUG=`$"{ALTR_STREAM_DEBUG:-false}
      - ALTR_STREAM_LOG_LEVEL=`$"{ALTR_STREAM_LOG_LEVEL:-INFO}
      - ALTR_STREAM_DEFAULT_CONNECTION_TIMEOUT_SEC=`$"{ALTR_STREAM_DEFAULT_CONNECTION_TIMEOUT_SEC:-5.0}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s

volumes:
  altr_stream_data:
    name: altr_stream_data
"@

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
# Screen: Docker Error
# ------------------------------------------------------------------------------
function Show-DockerErrorScreen ([bool]$isStopped) {
    if (-not $GumBin) { return $false }
    Render-ScreenTop 20
    $pad = Get-LayoutPadding 68 20
    $leftPad = $pad[0]

    if ($isStopped) {
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 --bold `
            "Docker Daemon Stopped" "" `
            "✗ Docker engine is not running or accessible." `
            "Altr Stream requires a responsive Docker Desktop engine." `
            "Please start Docker Desktop and verify the status is green."
    }
    else {
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 --bold `
            "Docker Required" "" `
            "✗ Docker Desktop was not found on this system." `
            "Docker and Docker Compose are required to run Altr Stream." `
            "Visit https://docs.docker.com/desktop/setup/install/windows-install/"
    }

    $choice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Select an action:" `
        "Start Docker Desktop" "Open Docker Guide" "Retry Detection" "Back to Main Menu"

    switch ($choice) {
        "Start Docker Desktop" {
            Start-Process "docker" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            return (Test-DockerEngine)
        }
        "Open Docker Guide" {
            Start-Process "https://docs.docker.com/desktop/setup/install/windows-install/"
        }
        "Retry Detection" {
            return (Test-DockerEngine)
        }
    }
    return $false
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
        $dockerStat = Get-DockerStatusText
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
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 --bold `
            "${sp1}${h1}" `
            "${sp2}${h2}" `
            "${sp3}${h3}" `
            "" `
            "  Docker Engine:  $dockerStat" `
            "  Altr Container: $altrStat" `
            "  Install Path:   $targetDir"

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
    $check = docker inspect altr-stream 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $check) { return $false }
    $cworkdir = (docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' altr-stream 2>$null)
    if (-not $cworkdir -or ($cworkdir.Trim() -ne $TargetDir.Trim())) {
        return $true
    }
    return $false
}

function Show-ExistingContainerDetails([string]$TargetContainer = "altr-stream", [string]$ReturnLabel = "Back to Conflict Menu") {
    $inspect = docker inspect $TargetContainer 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $inspect) {
        & $GumBin style --foreground 196 "Container '$TargetContainer' does not exist."
        Invoke-GumChoose --cursor="❯ " $ReturnLabel
        return
    }

    $cid = (docker inspect -f '{{.Id}}' $TargetContainer 2>$null)
    $cname = (docker inspect -f '{{.Name}}' $TargetContainer 2>$null) -replace '^/', ''
    $cstatus = (docker inspect -f '{{.State.Status}}' $TargetContainer 2>$null)
    $chealth = (docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $TargetContainer 2>$null)
    $cimage = (docker inspect -f '{{.Config.Image}}' $TargetContainer 2>$null)
    $ccreated = (docker inspect -f '{{.Created}}' $TargetContainer 2>$null)
    $cports = (docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}} {{end}}' $TargetContainer 2>$null)
    $cproject = (docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' $TargetContainer 2>$null)
    $cworkdir = (docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' $TargetContainer 2>$null)
    $cmounts = (docker inspect -f '{{range .Mounts}}{{.Name}}{{.Source}} -> {{.Destination}} ({{.Type}}) {{end}}' $TargetContainer 2>$null)
    $cversion = (docker inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' $TargetContainer 2>$null)
    if (-not $cversion) {
        if ($cimage -match ':([^:]+)$') { $cversion = $matches[1] } else { $cversion = "Unknown" }
    }

    $classification = if ($cimage -match "altr-stream") { "✓ Identified as an Altr Stream container" } else { "⚠ Notice: This container does NOT appear to belong to Altr Stream." }

    Clear-Host
    Render-ScreenTop 24
    $pad = Get-LayoutPadding 68 24
    $leftPad = $pad[0]
    & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 --align center --bold `
        "CONTAINER DETAILS" "" "$cname"

    $cidShort = if ($cid.Length -ge 12) { $cid.Substring(0, 12) } else { $cid }
    & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
        "Container Attributes:" "" `
        "  Name:           $cname" `
        "  ID:             $cidShort ($cid)" `
        "  Status:         $cstatus" `
        "  Health State:   $chealth" `
        "  Image:          $cimage" `
        "  Version:        $cversion" `
        "  Created:        $ccreated" `
        "  Ports:          $($cports ? $cports : 'None')" `
        "  Compose Proj:   $($cproject ? $cproject : 'None')" `
        "  Working Dir:    $($cworkdir ? $cworkdir : 'None')" `
        "  Mounts:         $($cmounts ? $cmounts : 'None')" "" `
        "Classification:" `
        "  $classification"

    Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" $ReturnLabel
}

function Handle-RemoveExistingContainer([string]$TargetDir) {
    $cid = (docker inspect -f '{{.Id}}' altr-stream 2>$null)
    $cname = (docker inspect -f '{{.Name}}' altr-stream 2>$null) -replace '^/', ''
    $cidShort = if ($cid.Length -ge 12) { $cid.Substring(0, 12) } else { $cid }

    Render-ScreenTop 18
    $pad = Get-LayoutPadding 68 18
    $leftPad = $pad[0]
    & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 `
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
    & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 `
        "CONFIRM CONTAINER REMOVAL" "" `
        "Are you sure you want to remove container `"altr-stream`"?" "" `
        "This removes ONLY the container. Persistent data stored in" `
        "the named volume `"altr_stream_data`" will NOT be deleted."

    $confirm = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Are you sure?" "Cancel" "Confirm Removal"
    if ($confirm -ne "Confirm Removal") { return $false }

    if ($GumBin) {
        & $GumBin spin --spinner dot --title "Removing conflicting container altr-stream..." -- powershell -Command "docker rm -f altr-stream"
    } else {
        docker rm -f altr-stream 2>$null
    }
    return $true
}

function Handle-UseExistingContainer([string]$TargetDir) {
    $inspect = docker inspect altr-stream 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $inspect) {
        & $GumBin style --foreground 196 "Container 'altr-stream' no longer exists."
        Start-Sleep -Seconds 1
        return $false
    }

    $cimage = (docker inspect -f '{{.Config.Image}}' altr-stream 2>$null)
    $cstatus = (docker inspect -f '{{.State.Status}}' altr-stream 2>$null)
    $cworkdir = (docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' altr-stream 2>$null)

    if ($cimage -notmatch "altr-stream") {
        Render-ScreenTop 16
        $pad = Get-LayoutPadding 68 16
        $leftPad = $pad[0]
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 `
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
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 `
            "CONTAINER STOPPED" "" `
            "The existing Altr Stream container is currently stopped." "" `
            "Status: $cstatus"

        $startChoice = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Would you like to start it now?" `
            "Start Container & Verify Health" "Back to Conflict Menu"
        if ($startChoice -ne "Start Container & Verify Health") { return $false }

        if ($GumBin) {
            & $GumBin spin --spinner dot --title "Starting container altr-stream..." -- powershell -Command "docker start altr-stream"
        } else {
            docker start altr-stream 2>$null
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
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 `
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
        & $GumBin style --margin "0 0 0 $leftPad" --border double --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
            "EXISTING ALTR STREAM FOUND"

        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
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
        $check = docker inspect altr-stream 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $check) {
            Invoke-InstallWorkflow $TargetDir
            return
        }

        $cid = (docker inspect -f '{{.Id}}' altr-stream 2>$null)
        $cname = (docker inspect -f '{{.Name}}' altr-stream 2>/dev/null) -replace '^/', ''
        $cstatus = (docker inspect -f '{{.State.Status}}' altr-stream 2>$null)
        $cimage = (docker inspect -f '{{.Config.Image}}' altr-stream 2>$null)
        $cworkdir = (docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' altr-stream 2>$null)
        $cidShort = if ($cid.Length -ge 12) { $cid.Substring(0, 12) } else { $cid }

        Render-ScreenTop 24
        $pad = Get-LayoutPadding 68 24
        $leftPad = $pad[0]
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 --align center --bold `
            "⚠ EXISTING CONTAINER DETECTED" "" `
            "A container named `"altr-stream`" already exists in Docker."

        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
            "Existing Container Info:" "" `
            "  Name:     $cname" `
            "  ID:       $cidShort" `
            "  Status:   $cstatus" `
            "  Image:    $cimage" `
            "  Path:     $($cworkdir ? $cworkdir : 'Unknown / Not set')"

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
                    & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "0 2" --width 68 `
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
                & $GumBin style --foreground 245 "Exited Altr Stream Setup Utility."
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

    if (-not (Test-DockerEngine)) {
        $dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
        if ($Action -ne "Menu") {
            Write-Error "ERROR: Docker engine is not running or accessible. Please start Docker Desktop."
            exit 1
        }
        $retry = Show-DockerErrorScreen ([bool]$dockerCmd)
        if (-not $retry) { return }
    }

    $compose = Get-ComposeCommand
    if (-not $compose) {
        if ($Action -ne "Menu") {
            Write-Error "ERROR: Docker Compose is required. Please install Docker Compose v2."
            exit 1
        }
        Render-ScreenTop 16
        $pad = Get-LayoutPadding 68 16
        $leftPad = $pad[0]
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 --bold `
            "Docker Compose Required" "" "✗ Docker Compose plugin was not found."
        Invoke-GumConfirm "Press Enter to return"
        return
    }

    # Interactive Install prompt
    if ($GumBin -and ($Action -eq "Menu")) {
        while ($true) {
            Render-ScreenTop 22
            $pad = Get-LayoutPadding 68 22
            $leftPad = $pad[0]
            & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 `
                "Install Altr Stream" "" `
                "Target Version:    v$Version" `
                "Installation Path: $targetDir" "" `
                "Prerequisites:" `
                "  ✓ Docker installed" `
                "  ✓ Docker daemon running" `
                "  ✓ Docker Compose available"

            $act = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" --header="Ready to proceed:" `
                "Install Altr Stream" "Change Installation Path" "Back to Main Menu"

            switch ($act) {
                "Install Altr Stream" { break }
                "Change Installation Path" {
                    $newPath = Invoke-GumInput --placeholder "Enter custom path" --value "$targetDir" --width 50
                    if ($newPath -and $newPath.Trim() -ne "") {
                        $targetDir = [System.IO.Path]::GetFullPath($newPath.Trim())
                        Save-InstallDirectory $targetDir
                    }
                }
                default { return }
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
            $cid = (docker inspect -f '{{.Id}}' altr-stream 2>$null)
            $cname = (docker inspect -f '{{.Name}}' altr-stream 2>$null) -replace '^/', ''
            $cstatus = (docker inspect -f '{{.State.Status}}' altr-stream 2>$null)
            $cimage = (docker inspect -f '{{.Config.Image}}' altr-stream 2>$null)
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
    Write-RuntimeFiles $targetDir

    # Stage 2: Persistent storage volume
    if ($GumBin -and ($Action -eq "Menu")) {
        & $GumBin spin --spinner dot --title "Preparing persistent storage volume (altr_stream_data)..." -- Start-Sleep -Milliseconds 300
    }
    try { $null = docker volume create altr_stream_data 2>$null } catch {}

    # Stage 3: Pulling image
    if ($GumBin -and ($Action -eq "Menu")) {
        & $GumBin spin --spinner dot --title "Pulling Altr Stream image ($AltrImage)..." -- `
            powershell -Command "$compose -f `"$targetDir\docker-compose.yml`" pull"
    }
    else {
        Invoke-Expression "$compose -f `"$targetDir\docker-compose.yml`" pull" 2>$null
    }

    # Stage 4: Starting container
    $startFailed = $false
    $dockerStartLog = Join-Path $targetDir ".docker_start.log"
    Remove-Item $dockerStartLog -Force -ErrorAction SilentlyContinue

    if ($GumBin -and ($Action -eq "Menu")) {
        & $GumBin spin --spinner dot --title "Starting container..." -- `
            powershell -Command "$compose -f `"$targetDir\docker-compose.yml`" up -d 2>&1 | Out-File -FilePath `"$dockerStartLog`""
        if ($LASTEXITCODE -ne 0) { $startFailed = $true }
    }
    else {
        powershell -Command "$compose -f `"$targetDir\docker-compose.yml`" up -d 2>&1 | Out-File -FilePath `"$dockerStartLog`""
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
            $failedReason = if ($firstLine) { $firstLine } else { "docker compose up -d encountered an error" }
        } else {
            $failedReason = "docker compose up -d encountered an error"
        }
    }

    # Stage 5: Polling Healthcheck
    if (-not $failedStage) {
        $maxAttempts = 30
        $healthy = $false
        for ($i = 1; $i -le $maxAttempts; $i++) {
            try {
                $resp = Invoke-RestMethod -Uri "$webUrl/api/v1/health" -TimeoutSec 2 -ErrorAction SilentlyContinue
                if ($resp) { $healthy = $true; break }
            }
            catch {}
            Start-Sleep -Seconds 1
        }

        if (-not $healthy) {
            $failedStage = "Waiting for Altr Stream health check"
            $failedReason = "Container health check timed out after $maxAttempts seconds at $webUrl"
        }
    }

    # Verification and screen transition
    if (Test-InstallationHealth $targetDir) {
        if ($GumBin -and ($Action -eq "Menu")) {
            Show-InstallSuccessScreen $targetDir
        }
        else {
            Write-Host "Altr Stream is installed and running at $webUrl" -ForegroundColor Green
        }
    }
    else {
        if ($GumBin -and ($Action -eq "Menu")) {
            Show-InstallFailureScreen $targetDir ($failedStage ? $failedStage : "Health Verification") ($failedReason ? $failedReason : "Altr Stream health verification failed") $failedTechnical
        }
        else {
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
        & $GumBin style --margin "0 0 0 $leftPad" --border double --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
            "✓ INSTALLATION COMPLETE" "" `
            "ALTR STREAM" "v$Version"

        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
            "Installation Summary:" "" `
            "  ✓ Docker Engine       Running" `
            "  ✓ Altr Stream         Running" `
            "  ✓ Container           Healthy" `
            "  ✓ Version             v$Version" `
            "  ✓ Installation Path   $TargetDir" `
            "  ✓ Persistent Data     Enabled (altr_stream_data)" `
            "  ✓ Web Interface       $webUrl"

        & $GumBin style --margin "0 0 0 $leftPad" --foreground 245 "Altr Stream is ready to use."

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
                & $GumBin style --foreground 245 "Exited Altr Stream Setup Utility."
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
        & $GumBin style --margin "0 0 0 $leftPad" --border double --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
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
                & $GumBin style --foreground 245 "Exited Altr Stream Setup Utility."
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
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 --align center --bold `
            "✕ INSTALLATION FAILED" "" `
            "Altr Stream could not be started successfully."

        $dockerStat = Get-DockerStatusText
        $altrStat = Get-AltrStatusText $TargetDir

        $diag = @(
            "Failure Diagnostics:", ""
            "  Stage:          $Stage"
            "  Reason:         $Reason"
        )
        if ($Technical) { $diag += "  Technical:      $Technical" }
        $diag += @(
            "", "Current State:",
            "  Docker Engine:  $dockerStat",
            "  Container:      $altrStat",
            "  Path:           $TargetDir"
        )

        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 @diag

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
                    $cidProj = (& $compose -f (Join-Path $TargetDir "docker-compose.yml") ps -q altr-stream 2>$null)
                    if ($cidProj) { $hasContainer = $true }
                }

                if (-not $hasContainer -or ($Stage -eq "Starting Altr Stream container")) {
                    Render-ScreenTop 20
                    $pad = Get-LayoutPadding 68 20
                    $leftPad = $pad[0]
                    & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 --align center --bold `
                        "CONTAINER LOGS"

                    $cidConf = (docker inspect -f '{{.Id}}' altr-stream 2>$null)
                    $cnameConf = (docker inspect -f '{{.Name}}' altr-stream 2>$null) -replace '^/', ''
                    $cstateConf = (docker inspect -f '{{.State.Status}}' altr-stream 2>$null)
                    $cidConfShort = if ($cidConf.Length -ge 12) { $cidConf.Substring(0, 12) } else { $cidConf }

                    $logLines = @(
                        "No logs are available for the new container because Docker failed",
                        "before the container could be created.", "",
                        "Docker reported:",
                        "  $($Technical ? $Technical : $Reason)"
                    )
                    if ($cidConf) {
                        $logLines += @(
                            "",
                            "Conflicting container:",
                            "  Name:  $cnameConf",
                            "  ID:    $cidConfShort",
                            "  State: $cstateConf"
                        )
                    }

                    & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 @logLines

                    $logAction = Invoke-GumChoose --cursor="❯ " --cursor.foreground="48" "View Container Details" "Back to Failure Menu"
                    if ($logAction -eq "View Container Details") {
                        Show-ExistingContainerDetails "altr-stream" "Back to Failure Menu"
                    }
                }
                else {
                    Clear-Host
                    Write-Host "--- Container Logs (last 30 lines) ---" -ForegroundColor Cyan
                    & $compose -f (Join-Path $TargetDir "docker-compose.yml") logs --tail 30 altr-stream
                    Write-Host "--------------------------------------" -ForegroundColor Cyan
                    Invoke-GumChoose --cursor="❯ " "Return to Failure Menu"
                }
            }
            "Back to Main Menu" {
                return
            }
            default {
                Clear-Host
                & $GumBin style --foreground 245 "Exited Altr Stream Setup Utility."
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
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 `
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
            & $GumBin style --margin "0 0 0 $leftPad" --border double --border-foreground 196 --padding "1 2" --width 68 --bold `
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
                & $GumBin style --foreground 214 "Confirmation text did not match. Application data will be preserved."
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
        docker volume rm -f altr_stream_data 2>$null
    }

    $volStat = if ($deleteConfirmed) { "DELETED" } else { "PRESERVED" }
    if ($GumBin -and ($Action -eq "Menu")) {
        Render-ScreenTop 20
        $pad = Get-LayoutPadding 68 20
        $leftPad = $pad[0]
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
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
    $daemonOk = Test-DockerEngine
    $containerOk = $false
    $healthOk = $false

    if ($compose -and $hasCompose) {
        $psOut = (Invoke-Expression "$compose -f `"$targetDir\docker-compose.yml`" ps 2>`$null") -join " "
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

        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 `
            "Repair Altr Stream" "" `
            "Diagnostic Checks:" `
            "  $(if ($hasDir) { '✓ Directory exists' } else { '✗ Directory missing' })" `
            "  $(if ($hasCompose) { '✓ docker-compose.yml present' } else { '✗ docker-compose.yml missing' })" `
            "  $(if ($daemonOk) { '✓ Docker engine responsive' } else { '✗ Docker daemon unreachable' })" `
            "  $(if ($containerOk) { '✓ Container active' } else { '⚠ Container stopped or missing' })" `
            "  $(if ($healthOk) { '✓ Healthcheck responding' } else { '✗ Healthcheck offline' })" "" `
            "Recommended Action:" `
            "Repair will restore configuration files, inspect the container," `
            "and safely recreate or recover it. Persistent data is preserved."

        $proceed = Invoke-GumConfirm "Proceed with Repair?"
        if (-not $proceed) { return }
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
    docker volume create altr_stream_data 2>$null | Out-Null
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
        $inspect = docker inspect altr-stream 2>$null
        if ($LASTEXITCODE -eq 0 -and $inspect) {
            $existingExists = $true
            $existingStatus = docker inspect -f '{{.State.Status}}' altr-stream 2>$null
            $existingImage = docker inspect -f '{{.Config.Image}}' altr-stream 2>$null
            $existingMounts = docker inspect -f '{{range .Mounts}}{{.Name}} {{end}}' altr-stream 2>$null

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
            Invoke-Expression "$compose -f `"$targetDir\docker-compose.yml`" pull 2>`$null"
        }

        # Safe removal of existing container to eliminate name collisions
        if ($existingExists) {
            if ($GumBin -and ($Action -eq "Menu")) {
                & $GumBin spin --spinner dot --title "Preparing canonical container altr-stream..." -- powershell -Command "docker stop altr-stream; docker rm altr-stream"
            } else {
                docker stop altr-stream 2>$null | Out-Null
                docker rm altr-stream 2>$null | Out-Null
            }
        }

        $recreateFailed = $false
        $logPath = Join-Path $targetDir ".docker_start.log"
        if (Test-Path $logPath) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }

        if ($GumBin -and ($Action -eq "Menu")) {
            & $GumBin spin --spinner dot --title "Recreating container..." -- powershell -Command "$compose -f `"$targetDir\docker-compose.yml`" up -d *>`"$logPath`""
            if ($LASTEXITCODE -ne 0) { $recreateFailed = $true }
        }
        else {
            Invoke-Expression "$compose -f `"$targetDir\docker-compose.yml`" up -d *>`"$logPath`""
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
            Show-RepairFailureScreen $targetDir ($failedStage ? $failedStage : "Health Verification") ($failedReason ? $failedReason : "Altr Stream health verification failed after repair") $failedTechnical
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
        & $GumBin style --margin "0 0 0 $leftPad" --border double --border-foreground 48 --padding "1 2" --width 68 --align center --bold `
            "✓ REPAIR COMPLETE" "" `
            "ALTR STREAM" "v$Version"

        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
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
                & $GumBin style --foreground 245 "Exited Altr Stream Setup Utility."
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
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 196 --padding "1 2" --width 68 --align center --bold `
            "✕ REPAIR FAILED"

        $dockerStat = Get-DockerStatusText
        $altrStat = Get-AltrStatusText $TargetDir

        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
            "Repair failed during:" `
            "  $Stage" "" `
            "Reason:" `
            "  $Reason" `
            $(if ($Technical) { "" } else { $null }) `
            $(if ($Technical) { "Technical Details:" } else { $null }) `
            $(if ($Technical) { "  $Technical" } else { $null }) "" `
            "Current State:" `
            "  Docker Engine: $dockerStat" `
            "  Container:     $altrStat" `
            "  Path:          $TargetDir"

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
                    $cidProj = (Invoke-Expression "$compose -f `"$TargetDir\docker-compose.yml`" ps -q altr-stream 2>`$null")
                    if ($cidProj) { $hasContainer = $true }
                }

                if (-not $hasContainer -or ($Stage -eq "Recreating container")) {
                    Render-ScreenTop 20
                    $pad = Get-LayoutPadding 68 20
                    $leftPad = $pad[0]
                    & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 214 --padding "1 2" --width 68 --align center --bold `
                        "CONTAINER LOGS"

                    & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 240 --padding "0 2" --width 68 `
                        "No logs are available for the recreated container because Docker" `
                        "encountered an error during container creation/startup." "" `
                        "Docker reported:" `
                        "  $(if ($Technical) { $Technical } else { $Reason })"

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
                & $GumBin style --foreground 245 "Exited Altr Stream Setup Utility."
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
    $dockerStat = Get-DockerStatusText
    $altrStat = Get-AltrStatusText $targetDir
    $webPort = Get-WebPort $targetDir
    $webUrl = Get-WebUrl $targetDir

    if ($GumBin -and ($Action -eq "Menu")) {
        Render-ScreenTop 22
        $pad = Get-LayoutPadding 68 22
        $leftPad = $pad[0]
        & $GumBin style --margin "0 0 0 $leftPad" --border rounded --border-foreground 39 --padding "1 2" --width 68 `
            "Altr Stream Installation Status" "" `
            "Installation:" `
            "  Configured Version: v$Version" `
            "  Target Directory:   $targetDir" `
            "  Canonical Image:    $AltrImage" "" `
            "Runtime & Container:" `
            "  Docker Engine:      $dockerStat" `
            "  Altr Container:     $altrStat" `
            "  Web Port:           $webPort" `
            "  Web Interface:      $webUrl" `
            "  Named Volume:       altr_stream_data"
        Invoke-GumChoose --cursor="❯ " --header="" "Return" | Out-Null
    }
    else {
        Write-Host "Altr Stream Installation Status: Configured Version v$Version at $targetDir"
        Write-Host "Docker: $dockerStat | Container: $altrStat | Web Interface: $webUrl"
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
