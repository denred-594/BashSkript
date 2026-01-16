<#
.SYNOPSIS
    Sendet einen Ordner per rsync/SSH an einen Linux Server.

.DESCRIPTION
    Dieses Skript verwendet rsync über SSH um Ordner sicher auf einen
    Linux Server zu übertragen. Kein Empfänger-Skript nötig!

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
    [int]$SSHPort = 22,

    [Parameter(Mandatory=$false)]
    [switch]$Delete,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
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
Write-Log "     Folder-SSH-Sender v1.0 (rsync)"
Write-Log "=========================================="

# Validierung: Quellordner prüfen
if (-not (Test-Path $SourceFolder)) {
    Write-Log "Ordner nicht gefunden: $SourceFolder" -Level "ERROR"
    exit 1
}

# Prüfen ob rsync verfügbar ist
$rsyncAvailable = Test-Command "rsync"
$scpAvailable = Test-Command "scp"
$sshAvailable = Test-Command "ssh"

if (-not $sshAvailable) {
    Write-Log "SSH nicht gefunden! Bitte OpenSSH installieren." -Level "ERROR"
    Write-Log "Windows: Settings > Apps > Optional Features > OpenSSH Client" -Level "WARN"
    exit 1
}

# Ordnerinfo anzeigen
$folderSize = Get-FolderSizeMB -Path $SourceFolder
$fileCount = (Get-ChildItem -Path $SourceFolder -Recurse -File -ErrorAction SilentlyContinue).Count
Write-Log "Quellordner: $SourceFolder"
Write-Log "Dateien: $fileCount | Groesse: $folderSize MB"
Write-Log "Ziel: ${RemoteUser}@${RemoteHost}:${RemotePath}"
Write-Log "SSH-Port: $SSHPort"

# SSH-Key Parameter aufbauen
$sshKeyParam = ""
if ($SSHKeyPath) {
    if (Test-Path $SSHKeyPath) {
        $sshKeyParam = "-i `"$SSHKeyPath`""
        Write-Log "SSH-Key: $SSHKeyPath" -Level "OK"
    } else {
        Write-Log "SSH-Key nicht gefunden: $SSHKeyPath" -Level "WARN"
    }
}

# Quellpfad für rsync/scp vorbereiten
# OHNE trailing slash = Ordner selbst wird kopiert (inkl. Ordnername)
# MIT trailing slash = Nur Inhalt wird kopiert
$sourcePath = $SourceFolder.TrimEnd('\', '/')

Write-Log "=========================================="

# Methode wählen: rsync (bevorzugt) oder scp (Fallback)
if ($rsyncAvailable) {
    Write-Log "Verwende rsync (inkrementell, effizient)" -Level "OK"

    # rsync Optionen aufbauen
    $rsyncOptions = @(
        "-avz",                          # archive, verbose, compress
        "--progress",                    # Fortschritt anzeigen
        "-e `"ssh -p $SSHPort $sshKeyParam`""  # SSH-Verbindung
    )

    if ($Delete) {
        $rsyncOptions += "--delete"      # Gelöschte Dateien auch auf Ziel löschen
        Write-Log "Option: --delete aktiv (synchronisiert Löschungen)" -Level "WARN"
    }

    if ($DryRun) {
        $rsyncOptions += "--dry-run"
        Write-Log "Option: --dry-run aktiv (keine echten Änderungen)" -Level "WARN"
    }

    $rsyncCmd = "rsync $($rsyncOptions -join ' ') `"$sourcePath`" `"${RemoteUser}@${RemoteHost}:${RemotePath}`""

    Write-Log "Befehl: $rsyncCmd" -Level "CMD"
    Write-Log "Starte Transfer..."

    try {
        # rsync direkt ausführen (nicht via Start-Process, um korrekten Exit-Code zu erhalten)
        $sshCmd = "ssh -p $SSHPort $sshKeyParam".Trim()

        # rsync mit & aufrufen für direkten Exit-Code
        & rsync -avz --progress `
            --exclude=.DS_Store `
            --exclude="._*" `
            --exclude=".Spotlight-*" `
            --exclude=.Trashes `
            -e $sshCmd `
            $sourcePath `
            "${RemoteUser}@${RemoteHost}:${RemotePath}"

        $exitCode = $LASTEXITCODE

        # Exit-Codes: 0 = OK, 23 = partial transfer (oft nur Warnung), 24 = vanished files (OK)
        if ($exitCode -eq 0) {
            Write-Log "=========================================="
            Write-Log "TRANSFER ERFOLGREICH ABGESCHLOSSEN" -Level "OK"
            Write-Log "Dateien sind jetzt unter: ${RemoteUser}@${RemoteHost}:${RemotePath}"
        } elseif ($exitCode -eq 23 -or $exitCode -eq 24) {
            Write-Log "=========================================="
            Write-Log "TRANSFER ABGESCHLOSSEN (mit Warnungen)" -Level "WARN"
            Write-Log "Dateien sind jetzt unter: ${RemoteUser}@${RemoteHost}:${RemotePath}"
        } else {
            Write-Log "rsync beendet mit Exit-Code: $exitCode" -Level "ERROR"
            exit $exitCode
        }
    }
    catch {
        Write-Log "Fehler bei rsync: $_" -Level "ERROR"
        exit 1
    }
}
else {
    # Fallback: scp verwenden
    Write-Log "rsync nicht gefunden - verwende scp (vollständige Kopie)" -Level "WARN"

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
}

exit 0
