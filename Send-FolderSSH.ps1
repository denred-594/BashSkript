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
    [int]$SSHPort = 22
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

if (-not $scpAvailable) {
    Write-Log "OpenSSH Client nicht gefunden!" -Level "ERROR"
    Write-Log "OpenSSH ist ein natives Windows-Feature (kein externes Programm)." -Level "WARN"
    Write-Log "Aktivierung per PowerShell (als Administrator):" -Level "WARN"
    Write-Log "  Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0" -Level "WARN"
    Write-Log "Oder: Einstellungen > Apps > Optionale Features > OpenSSH-Client" -Level "WARN"
    exit 1
}

# Ordnerinfo anzeigen
$folderSize = Get-FolderSizeMB -Path $SourceFolder
$fileCount = (Get-ChildItem -Path $SourceFolder -Recurse -File -ErrorAction SilentlyContinue).Count
Write-Log "Quellordner: $SourceFolder"
Write-Log "Dateien: $fileCount | Groesse: $folderSize MB"
Write-Log "Ziel: ${RemoteUser}@${RemoteHost}:${RemotePath}"
Write-Log "SSH-Port: $SSHPort"

# SSH-Key prüfen falls angegeben
if ($SSHKeyPath) {
    if (Test-Path $SSHKeyPath) {
        Write-Log "SSH-Key: $SSHKeyPath" -Level "OK"
    } else {
        Write-Log "SSH-Key nicht gefunden: $SSHKeyPath" -Level "WARN"
    }
}

Write-Log "=========================================="

# SCP Transfer durchführen (natives Windows OpenSSH)
Write-Log "Verwende SCP (nativer Windows OpenSSH Client)" -Level "OK"

$scpOptions = @(
    "-r",                            # rekursiv
    "-P", $SSHPort                   # Port
)

if ($SSHKeyPath -and (Test-Path $SSHKeyPath)) {
    $scpOptions += "-i", $SSHKeyPath
}

$scpCmd = "scp $($scpOptions -join ' ') `"$SourceFolder`" `"${RemoteUser}@${RemoteHost}:${RemotePath}`""

Write-Log "Befehl: $scpCmd" -Level "CMD"
Write-Log "Starte Transfer..."

try {
    $scpArgs = $scpOptions + @($SourceFolder, "${RemoteUser}@${RemoteHost}:${RemotePath}")
    $process = Start-Process -FilePath "scp" -ArgumentList $scpArgs -NoNewWindow -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        Write-Log "=========================================="
        Write-Log "TRANSFER ERFOLGREICH ABGESCHLOSSEN" -Level "OK"
        Write-Log "Dateien sind jetzt unter: ${RemoteUser}@${RemoteHost}:${RemotePath}"
    } else {
        Write-Log "scp beendet mit Exit-Code: $($process.ExitCode)" -Level "ERROR"
        exit $process.ExitCode
    }
}
catch {
    Write-Log "Fehler bei scp: $_" -Level "ERROR"
    exit 1
}

exit 0
