<#
.SYNOPSIS
    Sendet einen Ordner per SCP/SSH an einen Linux Server.

.DESCRIPTION
    Dieses Skript verwendet SCP (Secure Copy) über SSH um Ordner sicher auf einen
    Linux Server zu übertragen. Verwendet nur den nativen Windows OpenSSH Client.

.PARAMETER SourceFolder
    Der Pfad zum Ordner, der gesendet werden soll.

.PARAMETER RemoteHost
    SSH-Host (IP oder Domain).

.PARAMETER RemoteUser
    SSH-Benutzername.

.PARAMETER RemotePath
    Zielpfad auf dem Server.

.PARAMETER SSHKeyPath
    Optional: Pfad zum SSH Private Key.

.PARAMETER SSHPort
    Optional: SSH Port (Standard: 22).

.PARAMETER RemoteSubDir
    Optional: Unterordner auf dem Server (Standard: "current").

.EXAMPLE
    .\Send-FolderSSH.ps1 -SourceFolder "C:\Daten" -RemoteHost "192.168.1.100" -RemoteUser "admin" -RemotePath "/var/data"

.EXAMPLE
    .\Send-FolderSSH.ps1 -SourceFolder "C:\Daten" -RemoteHost "server.example.com" -RemoteUser "admin" -RemotePath "/var/data" -SSHKeyPath "~/.ssh/id_rsa"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceFolder,

    [Parameter(Mandatory=$true)]
    [string]$RemoteHost,

    [Parameter(Mandatory=$true)]
    [string]$RemoteUser,

    [Parameter(Mandatory=$true)]
    [string]$RemotePath,

    [Parameter(Mandatory=$false)]
    [string]$SSHKeyPath = "",

    [Parameter(Mandatory=$false)]
    [int]$SSHPort = 22,

    [Parameter(Mandatory=$false)]
    [string]$RemoteSubDir = "current",

    [Parameter(Mandatory=$false)]
    [switch]$NonInteractive
)

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        "CMD"   { "Cyan" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Normalize-RemotePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $p = $Path.Trim()
    if (-not $p.StartsWith("/")) {
        $p = "/" + $p
    }
    $p = $p.TrimEnd("/")
    return $p
}

function Escape-ForScpRemotePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    return ($Path -replace " ", "\\ ")
}

function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

function Get-FolderSizeMB {
    param([string]$Path)
    $size = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    return [math]::Round($size / 1MB, 2)
}

function Escape-ForSingleQuotes {
    param([string]$Value)
    if ($null -eq $Value) { return "" }
    $replacement = "'" + '"' + "'" + '"' + "'"
    return $Value -replace "'", $replacement
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$ArgumentList,
        [Parameter(Mandatory=$true)][string]$Description
    )

    $argString = ($ArgumentList | ForEach-Object { "$_" }) -join " "
    Write-Log "$Description" -Level "CMD"
    Write-Log "  $FilePath $argString" -Level "CMD"

    & $FilePath @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Log "$FilePath beendet mit Exit-Code: $exitCode" -Level "ERROR"
        exit $exitCode
    }
}

# ============== HAUPTPROGRAMM ==============

Write-Log "=========================================="
Write-Log "     Folder-SSH-Sender v2.0 (SCP)"
Write-Log "=========================================="

# Validierung: Quellordner prüfen
if (-not (Test-Path $SourceFolder)) {
    Write-Log "Ordner nicht gefunden: $SourceFolder" -Level "ERROR"
    exit 1
}

# Prüfen ob OpenSSH verfügbar ist (natives Windows-Feature)
$scpAvailable = Test-Command "scp"
$sshAvailable = Test-Command "ssh"

if (-not $scpAvailable) {
    Write-Log "OpenSSH Client nicht gefunden!" -Level "ERROR"
    Write-Log "OpenSSH ist ein natives Windows-Feature (kein externes Programm)." -Level "WARN"
    Write-Log "Aktivierung per PowerShell (als Administrator):" -Level "WARN"
    Write-Log "  Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -Level "WARN"
    Write-Log "Oder: Einstellungen > Apps > Optionale Features > OpenSSH-Client" -Level "WARN"
    exit 1
}

if (-not $sshAvailable) {
    Write-Log "ssh nicht gefunden! Bitte OpenSSH Client installieren." -Level "ERROR"
    exit 1
}

# Ordnerinfo anzeigen
$folderSize = Get-FolderSizeMB -Path $SourceFolder
$fileCount = (Get-ChildItem -Path $SourceFolder -Recurse -File -ErrorAction SilentlyContinue).Count
Write-Log "Quellordner: $SourceFolder"
Write-Log "Dateien: $fileCount | Groesse: $folderSize MB"
Write-Log "Ziel: ${RemoteUser}@${RemoteHost}:${RemotePath}"
Write-Log "SSH-Port: $SSHPort"
Write-Log "Remote Unterordner: $RemoteSubDir"

# SSH-Key prüfen falls angegeben
if ($SSHKeyPath) {
    if (Test-Path $SSHKeyPath) {
        Write-Log "SSH-Key: $SSHKeyPath" -Level "OK"
    } else {
        Write-Log "SSH-Key nicht gefunden: $SSHKeyPath" -Level "WARN"
    }
}

Write-Log "=========================================="

# Deterministischer Export-Upload: genau manifest.json + passende NDJSON-Datei (SCP-only)
Write-Log "Verwende SCP/SSH (nativer Windows OpenSSH Client)" -Level "OK"

$manifestPath = Join-Path $SourceFolder "manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Log "manifest.json nicht gefunden: $manifestPath" -Level "ERROR"
    exit 2
}

try {
    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
} catch {
    Write-Log "manifest.json konnte nicht gelesen/geparst werden: $_" -Level "ERROR"
    exit 3
}

$exportTyp = $manifest.export_typ
if (-not $exportTyp) {
    Write-Log "manifest.json: Feld 'export_typ' fehlt." -Level "ERROR"
    exit 4
}

Write-Log "export_typ: $exportTyp" -Level "OK"

$ndjsonFileName = $null
switch ($exportTyp) {
    "all"    { $ndjsonFileName = "articles.ndjson" }
    "update" { $ndjsonFileName = "articles_update.ndjson" }
    default {
        Write-Log "Unbekannter export_typ: '$exportTyp' (erwartet: all|update)" -Level "ERROR"
        exit 5
    }
}

Write-Log "Gewaehlte NDJSON-Datei: $ndjsonFileName" -Level "OK"

$ndjsonPath = Join-Path $SourceFolder $ndjsonFileName
if (-not (Test-Path $ndjsonPath)) {
    Write-Log "NDJSON-Datei nicht gefunden: $ndjsonPath" -Level "ERROR"
    exit 6
}

$remoteBasePath = Normalize-RemotePath $RemotePath
$remoteCurrentPath = "$remoteBasePath/$RemoteSubDir"
$remoteCurrentEsc = Escape-ForSingleQuotes $remoteCurrentPath

$manifestTmpRemote = "$remoteCurrentPath/manifest.json.tmp"
$ndjsonTmpRemote = "$remoteCurrentPath/$ndjsonFileName.tmp"

$manifestTmpRemoteEsc = Escape-ForSingleQuotes $manifestTmpRemote
$ndjsonTmpRemoteEsc = Escape-ForSingleQuotes $ndjsonTmpRemote

$articlesAllTmpRemoteEsc = Escape-ForSingleQuotes "$remoteCurrentPath/articles.ndjson.tmp"
$articlesUpdateTmpRemoteEsc = Escape-ForSingleQuotes "$remoteCurrentPath/articles_update.ndjson.tmp"

$scpOptions = @(
    "-P", $SSHPort
)

$sshOptions = @(
    "-p", $SSHPort
)

if ($NonInteractive) {
    $commonSshOptions = @(
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ConnectTimeout=15",
        "-o", "ServerAliveInterval=10",
        "-o", "ServerAliveCountMax=3",
        "-o", "PreferredAuthentications=publickey",
        "-o", "PasswordAuthentication=no",
        "-o", "KbdInteractiveAuthentication=no",
        "-o", "NumberOfPasswordPrompts=0"
    )

    $sshOptions += "-T"
    $sshOptions += "-n"
    $sshOptions += $commonSshOptions
    $scpOptions += $commonSshOptions
}

if ($SSHKeyPath -and (Test-Path $SSHKeyPath)) {
    $scpOptions += "-i", $SSHKeyPath
    $sshOptions += "-i", $SSHKeyPath
}

$remoteLogin = "${RemoteUser}@${RemoteHost}"

# (a) Remote-Setup: mkdir + rm tmp
$cleanupCmd = "mkdir -p '$remoteCurrentEsc' && rm -f '$manifestTmpRemoteEsc' '$articlesAllTmpRemoteEsc' '$articlesUpdateTmpRemoteEsc'"
Invoke-ExternalCommand -FilePath "ssh" -ArgumentList ($sshOptions + @($remoteLogin, $cleanupCmd)) -Description "Remote-Setup: mkdir + cleanup tmp"

# (b) Upload via scp (auf .tmp)
$manifestTmpRemoteScp = Escape-ForScpRemotePath $manifestTmpRemote
$ndjsonTmpRemoteScp = Escape-ForScpRemotePath $ndjsonTmpRemote

$remoteManifestSpec = "${remoteLogin}:$manifestTmpRemoteScp"
$remoteNdjsonSpec = "${remoteLogin}:$ndjsonTmpRemoteScp"

Invoke-ExternalCommand -FilePath "scp" -ArgumentList ($scpOptions + @($manifestPath, $remoteManifestSpec)) -Description "Upload: manifest.json -> manifest.json.tmp"
Invoke-ExternalCommand -FilePath "scp" -ArgumentList ($scpOptions + @($ndjsonPath, $remoteNdjsonSpec)) -Description "Upload: $ndjsonFileName -> $ndjsonFileName.tmp"

# (c) Atomar umbenennen via ssh (erst wenn beide Uploads ok)
$renameCmd = "mv '$manifestTmpRemoteEsc' '$remoteCurrentEsc/manifest.json' && mv '$ndjsonTmpRemoteEsc' '$remoteCurrentEsc/$ndjsonFileName'"
Invoke-ExternalCommand -FilePath "ssh" -ArgumentList ($sshOptions + @($remoteLogin, $renameCmd)) -Description "Remote-Rename: .tmp -> final (atomar)"

Write-Log "=========================================="
Write-Log "TRANSFER ERFOLGREICH ABGESCHLOSSEN" -Level "OK"
Write-Log "Ergebnis unter: ${RemoteUser}@${RemoteHost}:${remoteCurrentPath}"

exit 0
