param(
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$InternalRoot = Join-Path $RepoRoot "_interno"
$LogsDir = Join-Path $InternalRoot "logs"
$LogFile = Join-Path $LogsDir "instalacion_windows.log"
$VenvDir = Join-Path $InternalRoot "venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$VenvPythonw = Join-Path $VenvDir "Scripts\pythonw.exe"
$RequirementsFile = Join-Path $InternalRoot "requirements.txt"
$FlowScript = Join-Path $InternalRoot "ejecutar_flujo.py"
$InternalFfmpegDir = Join-Path $InternalRoot "herramientas\windows"
$InternalFfmpeg = Join-Path $InternalFfmpegDir "ffmpeg.exe"
$WinGetLinksDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"

New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

function Write-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $LogFile -Value "[$timestamp] $Message"
}

function Show-Info {
    param([string]$Message)
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($Message, "Procesar llamadas", "OK", "Information") | Out-Null
}

function Show-Error {
    param([string]$Message)
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($Message, "Procesar llamadas", "OK", "Error") | Out-Null
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Add-WinGetLinksToPath {
    if (Test-Path $WinGetLinksDir) {
        if (-not ($env:Path.Split(';') -contains $WinGetLinksDir)) {
            $env:Path = "$WinGetLinksDir;$env:Path"
        }
    }
}

function Get-PythonCommand {
    Add-WinGetLinksToPath

    $candidateExecutables = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python313\python.exe")
    )

    foreach ($candidate in $candidateExecutables) {
        if (Test-Path $candidate) {
            return [pscustomobject]@{ Exe = $candidate; Args = @() }
        }
    }

    if (Test-Command "py") {
        try {
            & py -3.12 -c "import sys" *> $null
            return [pscustomobject]@{ Exe = "py"; Args = @("-3.12") }
        } catch {
        }

        try {
            & py -3 -c "import sys" *> $null
            return [pscustomobject]@{ Exe = "py"; Args = @("-3") }
        } catch {
        }
    }

    if (Test-Command "python") {
        return [pscustomobject]@{ Exe = (Get-Command python).Source; Args = @() }
    }

    return $null
}

function Ensure-WinGet {
    Add-WinGetLinksToPath
    if (Test-Command "winget") {
        return
    }

    throw "Este Windows no tiene disponible winget. Instala 'App Installer' desde Microsoft Store y vuelve a pulsar el boton."
}

function Install-WithWinGet {
    param(
        [string]$Id,
        [string]$FriendlyName
    )

    Write-Log "Instalando $FriendlyName con winget."
    & winget install --exact --id $Id --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
}

function Ensure-Python {
    $pythonCommand = Get-PythonCommand
    if ($null -ne $pythonCommand) {
        Write-Log "Python ya disponible para bootstrap."
        return $pythonCommand
    }

    Ensure-WinGet
    Show-Info "Voy a preparar este Windows por primera vez. Puede tardar varios minutos y puede pedir permisos del sistema."
    Install-WithWinGet -Id "Python.Python.3.12" -FriendlyName "Python 3"
    Start-Sleep -Seconds 3

    $pythonCommand = Get-PythonCommand
    if ($null -eq $pythonCommand) {
        throw "No se ha podido localizar Python 3 despues de instalarlo."
    }

    return $pythonCommand
}

function Get-FfmpegPath {
    if (Test-Path $InternalFfmpeg) {
        return $InternalFfmpeg
    }

    Add-WinGetLinksToPath
    $ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($null -ne $ffmpegCommand) {
        return $ffmpegCommand.Source
    }

    $candidateExecutables = @(
        (Join-Path $WinGetLinksDir "ffmpeg.exe")
    )

    foreach ($candidate in $candidateExecutables) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $packageRoots = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"),
        (Join-Path $env:ProgramFiles "WinGet\Packages")
    )

    foreach ($root in $packageRoots) {
        if (Test-Path $root) {
            $match = Get-ChildItem -Path $root -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $match) {
                return $match.FullName
            }
        }
    }

    return $null
}

function Ensure-InternalFfmpeg {
    param([string]$SourcePath)

    New-Item -ItemType Directory -Force -Path $InternalFfmpegDir | Out-Null

    if ($SourcePath -ne $InternalFfmpeg) {
        Copy-Item -LiteralPath $SourcePath -Destination $InternalFfmpeg -Force
    }
}

function Ensure-Ffmpeg {
    $ffmpegPath = Get-FfmpegPath
    if ($null -ne $ffmpegPath) {
        Write-Log "FFmpeg ya disponible."
        Ensure-InternalFfmpeg -SourcePath $ffmpegPath
        return
    }

    Ensure-WinGet
    Install-WithWinGet -Id "Gyan.FFmpeg" -FriendlyName "FFmpeg"
    Start-Sleep -Seconds 3

    $ffmpegPath = Get-FfmpegPath
    if ($null -eq $ffmpegPath) {
        throw "No se ha podido localizar FFmpeg despues de instalarlo."
    }

    Ensure-InternalFfmpeg -SourcePath $ffmpegPath
}

function Test-VenvReady {
    if (-not (Test-Path $VenvPython)) {
        return $false
    }

    try {
        & $VenvPython -c "import whisper" *> $null
        return $true
    } catch {
        return $false
    }
}

function Ensure-Venv {
    $pythonCommand = Ensure-Python

    if (-not (Test-Path $VenvPython)) {
        Write-Log "Creando entorno interno de Windows."
        & $pythonCommand.Exe @($pythonCommand.Args + @("-m", "venv", $VenvDir))
    }

    if (-not (Test-VenvReady)) {
        Write-Log "Instalando dependencias internas de Windows."
        & $VenvPython -m pip install --upgrade pip setuptools wheel
        & $VenvPython -m pip install -r $RequirementsFile
    } else {
        Write-Log "El entorno interno ya estaba listo."
    }
}

function Start-Flow {
    if (Test-Path $VenvPythonw) {
        Write-Log "Lanzando flujo con pythonw."
        Start-Process -FilePath $VenvPythonw -ArgumentList @($FlowScript) -WorkingDirectory $RepoRoot -WindowStyle Hidden
        return
    }

    if (Test-Path $VenvPython) {
        Write-Log "Lanzando flujo con python."
        Start-Process -FilePath $VenvPython -ArgumentList @($FlowScript) -WorkingDirectory $RepoRoot -WindowStyle Hidden
        return
    }

    throw "No se ha encontrado el Python interno para arrancar el flujo."
}

try {
    Write-Log "Inicio de preparacion de Windows."
    Ensure-Venv
    Ensure-Ffmpeg
    if ($NoLaunch) {
        Write-Log "Validacion completada sin lanzar el flujo."
    } else {
        Start-Flow
    }
    Write-Log "Preparacion completada."
} catch {
    $message = $_.Exception.Message
    Write-Log "ERROR: $message"
    Show-Error $message
    exit 1
}
