param(
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptRoot
$InternalRoot = Join-Path $RepoRoot "_interno"
$LogsDir = Join-Path $InternalRoot "logs"
$LogFile = Join-Path $LogsDir "instalacion_windows.log"
$BootstrapStatusFile = Join-Path $LogsDir "preparacion_windows_status.json"
$RequirementsFile = Join-Path $InternalRoot "requirements.txt"
$FlowScript = Join-Path $InternalRoot "ejecutar_flujo.py"
$BootstrapWindowScript = Join-Path $InternalRoot "ventana_preparacion_windows.ps1"
$InternalFfmpegDir = Join-Path $InternalRoot "herramientas\windows"
$InternalFfmpeg = Join-Path $InternalFfmpegDir "ffmpeg.exe"
$RuntimeWindowsDir = Join-Path $InternalRoot "runtime\windows"
$VisibleDiagnosticFile = Join-Path $RepoRoot "DIAGNOSTICO - ultimo error.txt"
$BootstrapLockFile = Join-Path $LogsDir "preparacion_windows.lock"
$UserRuntimeRoot = if ($env:PROCESAR_LLAMADAS_RUNTIME_ROOT) {
    $env:PROCESAR_LLAMADAS_RUNTIME_ROOT
} else {
    Join-Path $env:LOCALAPPDATA "ProcesarLlamadas"
}
New-Item -ItemType Directory -Force -Path $UserRuntimeRoot | Out-Null
$UserRuntimeRoot = (Get-Item -LiteralPath $UserRuntimeRoot).FullName
$LocalPythonDir = Join-Path $UserRuntimeRoot "python"
$LocalPythonExe = Join-Path $LocalPythonDir "python.exe"
$DownloadsDir = Join-Path $UserRuntimeRoot "downloads"
$PythonInstallerPath = Join-Path $DownloadsDir "python-3.10.11-amd64.exe"
$PythonInstallerUrl = "https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe"
$PythonInstallerLog = Join-Path $LogsDir "instalacion_python_windows.log"
$FfmpegZipPath = Join-Path $DownloadsDir "ffmpeg-release-essentials.zip"
$FfmpegZipUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
$ForceLocalPython = $env:PROCESAR_LLAMADAS_FORZAR_PYTHON_LOCAL -eq "1"
$ForceLocalFfmpeg = $env:PROCESAR_LLAMADAS_FORZAR_FFMPEG_LOCAL -eq "1"
$script:ShownBootstrapNotice = $false
$script:SetupStage = "inicio"
$script:BootstrapLockHandle = $null
$script:ProjectRuntimeKey = $null
$script:ProjectRuntimeRoot = $null
$script:VenvDir = $null
$script:VenvPython = $null
$script:VenvPythonw = $null
$script:BootstrapWindowStarted = $false
$script:BootstrapSessionId = [guid]::NewGuid().ToString("N")

New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
New-Item -ItemType Directory -Force -Path $DownloadsDir | Out-Null
New-Item -ItemType Directory -Force -Path $RuntimeWindowsDir | Out-Null

function Write-Log {
    param([string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -LiteralPath $LogFile -Value "[$timestamp] $Message"
}

function Quote-Argument {
    param([string]$Value)

    return '"' + $Value.Replace('"', '\"') + '"'
}

function Write-BootstrapStatus {
    param(
        [string]$Status,
        [string]$Detail,
        [bool]$Indeterminate = $true,
        [int]$Percent = 0,
        [bool]$Close = $false
    )

    if ($env:PROCESAR_LLAMADAS_SILENCIOSO -eq "1") {
        return
    }

    $payload = [ordered]@{
        session_id = $script:BootstrapSessionId
        status = $Status
        detail = $Detail
        indeterminate = $Indeterminate
        percent = $Percent
        close = $Close
    } | ConvertTo-Json -Compress

    Set-Content -LiteralPath $BootstrapStatusFile -Value $payload -Encoding UTF8
}

function Start-BootstrapWindow {
    if ($script:BootstrapWindowStarted) {
        return
    }

    if ($env:PROCESAR_LLAMADAS_SILENCIOSO -eq "1") {
        return
    }

    if (-not (Test-Path $BootstrapWindowScript)) {
        return
    }

    $script:BootstrapWindowStarted = $true
    Write-BootstrapStatus -Status "Preparando proceso..." -Detail "Arrancando la preparacion de Windows."

    $arguments = @(
        "-NoLogo"
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        (Quote-Argument $BootstrapWindowScript)
        "-SessionId"
        $script:BootstrapSessionId
        "-StatusFile"
        (Quote-Argument $BootstrapStatusFile)
        "-LogFile"
        (Quote-Argument $LogFile)
    ) -join " "

    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WorkingDirectory $RepoRoot -WindowStyle Hidden | Out-Null
}

function Update-BootstrapWindow {
    param(
        [string]$Status,
        [string]$Detail
    )

    Write-BootstrapStatus -Status $Status -Detail $Detail
}

function Close-BootstrapWindow {
    if ($env:PROCESAR_LLAMADAS_SILENCIOSO -eq "1") {
        return
    }

    if (-not (Test-Path $BootstrapStatusFile)) {
        return
    }

    Write-BootstrapStatus -Status "Proceso en marcha" -Detail "Abriendo la ventana principal." -Close $true
}

function Get-ProjectRuntimeKey {
    if ($null -ne $script:ProjectRuntimeKey) {
        return $script:ProjectRuntimeKey
    }

    $normalized = $RepoRoot.Trim().ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $hashText = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
    $script:ProjectRuntimeKey = $hashText.Substring(0, 16)
    return $script:ProjectRuntimeKey
}

function Get-ProjectRuntimeRoot {
    if ($null -ne $script:ProjectRuntimeRoot) {
        return $script:ProjectRuntimeRoot
    }

    $script:ProjectRuntimeRoot = Join-Path $UserRuntimeRoot ("projects\" + (Get-ProjectRuntimeKey))
    New-Item -ItemType Directory -Force -Path $script:ProjectRuntimeRoot | Out-Null
    return $script:ProjectRuntimeRoot
}

function Get-VenvDir {
    if ($null -ne $script:VenvDir) {
        return $script:VenvDir
    }

    $script:VenvDir = Join-Path (Get-ProjectRuntimeRoot) "venv"
    return $script:VenvDir
}

function Get-VenvPython {
    if ($null -ne $script:VenvPython) {
        return $script:VenvPython
    }

    $script:VenvPython = Join-Path (Get-VenvDir) "Scripts\python.exe"
    return $script:VenvPython
}

function Get-VenvPythonw {
    if ($null -ne $script:VenvPythonw) {
        return $script:VenvPythonw
    }

    $script:VenvPythonw = Join-Path (Get-VenvDir) "Scripts\pythonw.exe"
    return $script:VenvPythonw
}

function Acquire-BootstrapLock {
    try {
        $script:BootstrapLockHandle = [System.IO.File]::Open(
            $BootstrapLockFile,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )

        $script:BootstrapLockHandle.SetLength(0)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("PID=$PID`r`nStarted=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $script:BootstrapLockHandle.Write($bytes, 0, $bytes.Length)
        $script:BootstrapLockHandle.Flush()
        return $true
    } catch [System.IO.IOException] {
        return $false
    }
}

function Release-BootstrapLock {
    if ($null -ne $script:BootstrapLockHandle) {
        $script:BootstrapLockHandle.Dispose()
        $script:BootstrapLockHandle = $null
    }
}

function Clear-VisibleDiagnostic {
    if (Test-Path $VisibleDiagnosticFile) {
        Remove-Item -LiteralPath $VisibleDiagnosticFile -Force -ErrorAction SilentlyContinue
    }
}

function Clear-BootstrapStatus {
    if (Test-Path $BootstrapStatusFile) {
        Remove-Item -LiteralPath $BootstrapStatusFile -Force -ErrorAction SilentlyContinue
    }
}

function Unblock-IfPossible {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return
    }

    try {
        Unblock-File -Path $Path -ErrorAction Stop
    } catch {
    }
}

function Get-FriendlySetupSummary {
    param([string]$Message)

    $lower = $Message.ToLowerInvariant()
    $stage = $script:SetupStage.ToLowerInvariant()

    if ($lower.Contains("ruta demasiado larga") -or $lower.Contains("long path")) {
        return "La carpeta donde se ha extraido el proyecto tiene una ruta demasiado larga para este Windows. Muevela a una ruta mas corta y vuelve a intentarlo."
    }

    if (
        $lower.Contains("unable to connect") -or
        $lower.Contains("the remote name could not be resolved") -or
        $lower.Contains("no such host is known") -or
        $lower.Contains("ssl") -or
        $lower.Contains("certificate") -or
        $lower.Contains("proxy") -or
        $lower.Contains("407") -or
        $lower.Contains("connection") -or
        $lower.Contains("download") -or
        $lower.Contains("pypi.org") -or
        $lower.Contains("files.pythonhosted.org") -or
        $lower.Contains("python.org") -or
        $lower.Contains("gyan.dev")
    ) {
        return "No se ha podido descargar uno de los componentes necesarios. Comprueba internet o si la red corporativa bloquea la descarga."
    }

    if ($lower.Contains("access is denied") -or $lower.Contains("denied") -or $lower.Contains("unauthorizedaccess")) {
        return "Windows ha bloqueado parte de la preparacion automatica. Comprueba permisos y vuelve a intentarlo."
    }

    if ($lower.Contains("whisper") -or $lower.Contains("torch") -or $lower.Contains("pip") -or $lower.Contains("no matching distribution")) {
        return "No se han podido instalar las dependencias internas del proyecto. Comprueba internet y vuelve a intentarlo."
    }

    if ($lower.Contains("ffmpeg") -or $stage.Contains("ffmpeg")) {
        return "No se ha podido preparar FFmpeg automaticamente en este Windows."
    }

    if ($lower.Contains("python") -or $stage.Contains("python") -or $stage.Contains("entorno")) {
        return "No se ha podido preparar Python automaticamente en este Windows."
    }

    if ($lower.Contains("carpeta del proyecto no esta completa") -or $lower.Contains("falta el archivo interno")) {
        return "La carpeta del proyecto no esta completa o se esta ejecutando desde un zip sin extraer."
    }

    return "No se ha podido preparar este Windows automaticamente."
}

function Write-VisibleDiagnostic {
    param(
        [string]$Summary,
        [string]$Details
    )

    $logContents = if (Test-Path $LogFile) { Get-Content -LiteralPath $LogFile -Raw } else { "" }
    $report = @(
        "DIAGNOSTICO DEL ULTIMO ERROR",
        "",
        "Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Paso del preparador: $script:SetupStage",
        "Carpeta del proyecto: $RepoRoot",
        "Log de instalacion: $LogFile",
        "",
        "RESUMEN",
        $Summary,
        "",
        "LOG DE INSTALACION",
        $(if ([string]::IsNullOrWhiteSpace($logContents)) { "(Sin contenido)" } else { $logContents.TrimEnd() }),
        "",
        "DETALLE TECNICO",
        $(if ([string]::IsNullOrWhiteSpace($Details)) { "(Sin detalle)" } else { $Details.TrimEnd() }),
        ""
    ) -join "`r`n"

    Set-Content -LiteralPath $VisibleDiagnosticFile -Value $report -Encoding UTF8
    return $VisibleDiagnosticFile
}

function Show-Info {
    param([string]$Message)

    if ($env:PROCESAR_LLAMADAS_SILENCIOSO -eq "1") {
        [Console]::WriteLine($Message)
        return
    }

    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($Message, "Procesar llamadas", "OK", "Information") | Out-Null
}

function Show-Error {
    param([string]$Message)

    if ($env:PROCESAR_LLAMADAS_SILENCIOSO -eq "1") {
        [Console]::Error.WriteLine($Message)
        return
    }

    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($Message, "Procesar llamadas", "OK", "Error") | Out-Null
}

function Show-FirstRunNotice {
    if ($script:ShownBootstrapNotice) {
        return
    }

    $script:ShownBootstrapNotice = $true
    Update-BootstrapWindow -Status "Preparando Windows por primera vez" -Detail "Puede tardar varios minutos. No hace falta volver a pulsar el boton."
}

function Show-AlreadyRunningNotice {
    Close-BootstrapWindow
    Show-Info "Ya se esta preparando o ejecutando el proceso en esta carpeta. Espera a que termine o a que aparezca la ventana de progreso."
}

function Test-Command {
    param([string]$Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-RealPythonPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    if (-not (Test-Path $Path)) {
        return $false
    }

    return $Path -notlike "*\WindowsApps\python*.exe"
}

function Test-WorkingPythonCommand {
    param(
        [string]$Exe,
        [string[]]$Args = @()
    )

    if ([string]::IsNullOrWhiteSpace($Exe)) {
        return $false
    }

    try {
        & $Exe @($Args + @("-c", "import tkinter, venv")) *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Invoke-NativeCommandChecked {
    param(
        [string]$Exe,
        [string[]]$ArgumentList,
        [string]$FriendlyName
    )

    $output = & $Exe @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE

    foreach ($line in $output) {
        Write-Log ([string]$line)
    }

    if ($exitCode -ne 0) {
        $joinedOutput = ($output | ForEach-Object { [string]$_ }) -join "`n"
        if ($joinedOutput -match "Windows Long Path support enabled" -or $joinedOutput -match "does not have Windows Long Path support enabled") {
            throw "La carpeta donde se ha extraido el proyecto tiene una ruta demasiado larga para este Windows. Mueve la carpeta a una ruta mas corta y vuelve a intentarlo."
        }

        throw "$FriendlyName ha fallado con codigo de salida $exitCode."
    }
}

function Get-RegistryPythonCommand {
    $registryKeys = @(
        "HKCU:\Software\Python\PythonCore\3.10\InstallPath",
        "HKCU:\Software\Python\PythonCore\3.11\InstallPath",
        "HKCU:\Software\Python\PythonCore\3.12\InstallPath",
        "HKCU:\Software\Python\PythonCore\3.13\InstallPath",
        "HKLM:\Software\Python\PythonCore\3.10\InstallPath",
        "HKLM:\Software\Python\PythonCore\3.11\InstallPath",
        "HKLM:\Software\Python\PythonCore\3.12\InstallPath",
        "HKLM:\Software\Python\PythonCore\3.13\InstallPath",
        "HKLM:\Software\WOW6432Node\Python\PythonCore\3.10\InstallPath",
        "HKLM:\Software\WOW6432Node\Python\PythonCore\3.11\InstallPath",
        "HKLM:\Software\WOW6432Node\Python\PythonCore\3.12\InstallPath",
        "HKLM:\Software\WOW6432Node\Python\PythonCore\3.13\InstallPath"
    )

    foreach ($key in $registryKeys) {
        $item = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            continue
        }

        $candidates = @(
            $item.ExecutablePath,
            (Join-Path ($item.'(default)') "python.exe"),
            $item.'(default)'
        )

        foreach ($candidate in $candidates) {
            if ((Test-RealPythonPath $candidate) -and (Test-WorkingPythonCommand -Exe $candidate)) {
                return [pscustomobject]@{ Exe = $candidate; Args = @() }
            }
        }
    }

    return $null
}

function Invoke-Download {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [string]$FriendlyName
    )

    if (Test-Path $DestinationPath) {
        $existingFile = Get-Item -LiteralPath $DestinationPath -ErrorAction SilentlyContinue
        if ($null -ne $existingFile -and $existingFile.Length -gt 0) {
            Write-Log "$FriendlyName ya descargado."
            Unblock-IfPossible -Path $DestinationPath
            return
        }

        Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Descargando $FriendlyName desde $Url"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DestinationPath) | Out-Null
    Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing
    Unblock-IfPossible -Path $DestinationPath
}

function Find-AnyPythonCommand {
    if (Test-Path $LocalPythonExe) {
        return [pscustomobject]@{ Exe = $LocalPythonExe; Args = @() }
    }

    $registryPython = Get-RegistryPythonCommand
    if ($null -ne $registryPython) {
        return $registryPython
    }

    $candidateExecutables = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python310\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\python.exe"),
        (Join-Path $env:ProgramFiles "Python310\python.exe"),
        (Join-Path $env:ProgramFiles "Python311\python.exe"),
        (Join-Path $env:ProgramFiles "Python312\python.exe"),
        (Join-Path $env:ProgramFiles "Python313\python.exe")
    )

    foreach ($candidate in $candidateExecutables) {
        if ((Test-RealPythonPath $candidate) -and (Test-WorkingPythonCommand -Exe $candidate)) {
            return [pscustomobject]@{ Exe = $candidate; Args = @() }
        }
    }

    if (Test-Command "py") {
        try {
            if (Test-WorkingPythonCommand -Exe "py" -Args @("-3.12")) {
                return [pscustomobject]@{ Exe = "py"; Args = @("-3.12") }
            }
        } catch {
        }

        try {
            if (Test-WorkingPythonCommand -Exe "py" -Args @("-3")) {
                return [pscustomobject]@{ Exe = "py"; Args = @("-3") }
            }
        } catch {
        }
    }

    if (Test-Command "python") {
        $pythonPath = (Get-Command python).Source
        if ((Test-RealPythonPath $pythonPath) -and (Test-WorkingPythonCommand -Exe $pythonPath)) {
            return [pscustomobject]@{ Exe = $pythonPath; Args = @() }
        }
    }

    return $null
}

function Get-PythonCommand {
    if ((Test-Path $LocalPythonExe) -and (Test-WorkingPythonCommand -Exe $LocalPythonExe)) {
        return [pscustomobject]@{ Exe = $LocalPythonExe; Args = @() }
    }

    if ($ForceLocalPython) {
        return $null
    }

    return Find-AnyPythonCommand
}

function Install-LocalPython {
    if (Test-Path $LocalPythonExe) {
        Write-Log "Python local ya disponible."
        return [pscustomobject]@{ Exe = $LocalPythonExe; Args = @() }
    }

    Show-FirstRunNotice
    $script:SetupStage = "descargando Python"
    Update-BootstrapWindow -Status "Descargando Python" -Detail "Preparando el runtime base de Windows."
    Invoke-Download -Url $PythonInstallerUrl -DestinationPath $PythonInstallerPath -FriendlyName "Python"
    Unblock-IfPossible -Path $PythonInstallerPath
    $script:SetupStage = "instalando Python"
    Update-BootstrapWindow -Status "Instalando Python" -Detail "Windows esta preparando los componentes base."
    Write-Log "Instalando Python local en $LocalPythonDir"

    if (Test-Path $LocalPythonDir) {
        Remove-Item -LiteralPath $LocalPythonDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $installerArgs = @(
        "/quiet",
        "/log",
        $PythonInstallerLog,
        "InstallAllUsers=0",
        "Include_launcher=0",
        "InstallLauncherAllUsers=0",
        "PrependPath=0",
        "Shortcuts=0",
        "CompileAll=0",
        "Include_test=0",
        "Include_doc=0",
        "Include_dev=0",
        "Include_debug=0",
        "Include_symbols=0",
        "Include_pip=1",
        "Include_tcltk=1",
        "SimpleInstall=0",
        "TargetDir=$LocalPythonDir"
    )

    $process = Start-Process -FilePath $PythonInstallerPath -ArgumentList $installerArgs -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010, 1638, -2147023274)) {
        throw "No se ha podido instalar Python automaticamente. Codigo de salida: $($process.ExitCode)"
    }

    $script:SetupStage = "validando Python"
    Update-BootstrapWindow -Status "Validando Python" -Detail "Comprobando que Python ha quedado listo."
    $resolvedPython = Find-AnyPythonCommand
    if ($null -eq $resolvedPython) {
        throw "Python parecia instalarse bien, pero no se ha encontrado en ninguna ruta valida."
    }

    Invoke-NativeCommandChecked -Exe $resolvedPython.Exe -ArgumentList ($resolvedPython.Args + @("-c", "import tkinter, venv")) -FriendlyName "La validacion de Python"
    Write-Log "Python preparado correctamente: $($resolvedPython.Exe)"
    return $resolvedPython
}

function Ensure-Python {
    $pythonCommand = Get-PythonCommand
    if ($null -ne $pythonCommand) {
        Write-Log "Python disponible: $($pythonCommand.Exe)"
        Update-BootstrapWindow -Status "Python listo" -Detail "Ya hay un Python valido en este equipo."
        return $pythonCommand
    }

    return Install-LocalPython
}

function Get-FfmpegPath {
    $InternalFfmpeg = Join-Path $InternalFfmpegDir "ffmpeg.exe"

    if (Test-Path $InternalFfmpeg) {
        $internalItem = Get-Item -LiteralPath $InternalFfmpeg -ErrorAction SilentlyContinue
        if ($null -ne $internalItem -and $internalItem.Length -gt 0) {
            Unblock-IfPossible -Path $InternalFfmpeg
            return $InternalFfmpeg
        }

        Remove-Item -LiteralPath $InternalFfmpeg -Force -ErrorAction SilentlyContinue
    }

    if ($ForceLocalFfmpeg) {
        return $null
    }

    $ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($null -ne $ffmpegCommand -and (Test-Path $ffmpegCommand.Source)) {
        return $ffmpegCommand.Source
    }

    return $null
}

function Ensure-InternalFfmpeg {
    param([string]$SourcePath)

    $InternalFfmpeg = Join-Path $InternalFfmpegDir "ffmpeg.exe"
    New-Item -ItemType Directory -Force -Path $InternalFfmpegDir | Out-Null

    if ($SourcePath -ne $InternalFfmpeg) {
        Copy-Item -LiteralPath $SourcePath -Destination $InternalFfmpeg -Force
    }

    Unblock-IfPossible -Path $InternalFfmpeg
}

function Install-LocalFfmpeg {
    Show-FirstRunNotice
    $script:SetupStage = "descargando FFmpeg"
    Update-BootstrapWindow -Status "Descargando FFmpeg" -Detail "Preparando la herramienta de audio y video."
    Invoke-Download -Url $FfmpegZipUrl -DestinationPath $FfmpegZipPath -FriendlyName "FFmpeg"

    $extractDir = Join-Path $DownloadsDir "ffmpeg-extract"
    if (Test-Path $extractDir) {
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $script:SetupStage = "descomprimiendo FFmpeg"
    Update-BootstrapWindow -Status "Preparando FFmpeg" -Detail "Descomprimiendo los archivos internos."
    Write-Log "Descomprimiendo FFmpeg."
    Expand-Archive -Path $FfmpegZipPath -DestinationPath $extractDir -Force

    $ffmpegExecutable = Get-ChildItem -Path $extractDir -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $ffmpegExecutable) {
        throw "No se ha encontrado ffmpeg.exe despues de descomprimir FFmpeg."
    }

    $script:SetupStage = "copiando FFmpeg"
    Update-BootstrapWindow -Status "Copiando FFmpeg" -Detail "Guardando FFmpeg dentro del proyecto."
    Ensure-InternalFfmpeg -SourcePath $ffmpegExecutable.FullName
    Write-Log "FFmpeg local preparado correctamente."
}

function Ensure-Ffmpeg {
    $ffmpegPath = Get-FfmpegPath
    if ($null -ne $ffmpegPath) {
        Write-Log "FFmpeg disponible: $ffmpegPath"
        Update-BootstrapWindow -Status "FFmpeg listo" -Detail "La herramienta de audio y video ya esta disponible."
        Ensure-InternalFfmpeg -SourcePath $ffmpegPath
        return
    }

    Install-LocalFfmpeg
}

function Test-VenvReady {
    $VenvPython = Get-VenvPython

    if (-not (Test-Path $VenvPython)) {
        return $false
    }

    try {
        & $VenvPython -c "import whisper, tkinter" *> $null
        return $true
    } catch {
        return $false
    }
}

function Ensure-Venv {
    $pythonCommand = Ensure-Python
    $VenvDir = Get-VenvDir
    $VenvPython = Get-VenvPython
    $venvMarker = Join-Path $VenvDir "pyvenv.cfg"

    Update-BootstrapWindow -Status "Preparando entorno interno" -Detail "Comprobando el runtime del proyecto."

    if ((Test-Path $VenvDir) -and (-not (Test-Path $venvMarker))) {
        Write-Log "El entorno interno estaba incompleto. Lo recreo desde cero."
        Remove-Item -LiteralPath $VenvDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ((Test-Path $VenvDir) -and (-not (Test-Path $VenvPython))) {
        Write-Log "El Python interno no estaba disponible. Rehago el entorno interno."
        Remove-Item -LiteralPath $VenvDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ((Test-Path $VenvDir) -and (-not (Test-VenvReady))) {
        Write-Log "El entorno interno existia, pero no estaba listo. Lo recreo desde cero."
        Remove-Item -LiteralPath $VenvDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path $VenvPython)) {
        Show-FirstRunNotice
        $script:SetupStage = "creando entorno interno"
        Update-BootstrapWindow -Status "Creando entorno interno" -Detail "Montando el entorno aislado del proyecto."
        Write-Log "Creando entorno interno de Windows."
        Write-Log "Ruta del entorno interno: $VenvDir"
        Invoke-NativeCommandChecked -Exe $pythonCommand.Exe -ArgumentList ($pythonCommand.Args + @("-m", "venv", $VenvDir)) -FriendlyName "La creacion del entorno interno"
    }

    if (-not (Test-VenvReady)) {
        Show-FirstRunNotice
        $script:SetupStage = "instalando dependencias internas"
        Update-BootstrapWindow -Status "Instalando dependencias internas" -Detail "Descargando e instalando Whisper y el resto de componentes."
        Write-Log "Instalando dependencias internas de Windows."
        Invoke-NativeCommandChecked -Exe $VenvPython -ArgumentList @("-m", "pip", "install", "--disable-pip-version-check", "--no-input", "-r", $RequirementsFile) -FriendlyName "La instalacion de dependencias internas"
    }

    if (-not (Test-VenvReady)) {
        throw "El entorno interno se ha creado, pero Whisper no ha quedado instalado correctamente."
    } else {
        Write-Log "El entorno interno ya estaba listo."
    }
}

function Start-Flow {
    $VenvPythonw = Get-VenvPythonw
    $VenvPython = Get-VenvPython
    $quotedFlowScript = Quote-Argument $FlowScript

    Update-BootstrapWindow -Status "Abriendo la ventana del proceso" -Detail "En unos segundos veras la ventana principal."

    if (Test-Path $VenvPythonw) {
        Write-Log "Lanzando flujo con pythonw."
        $process = Start-Process -FilePath $VenvPythonw -ArgumentList $quotedFlowScript -WorkingDirectory $RepoRoot -PassThru
        Start-Sleep -Milliseconds 1200
        if (-not $process.HasExited -or (Test-Path (Join-Path $LogsDir "ultima_ejecucion.txt"))) {
            Close-BootstrapWindow
            return
        }

        Write-Log "pythonw no ha dejado el flujo arrancado. Intento la via de respaldo con python."
    }

    if (Test-Path $VenvPython) {
        Write-Log "Lanzando flujo con python."
        $process = Start-Process -FilePath $VenvPython -ArgumentList $quotedFlowScript -WorkingDirectory $RepoRoot -PassThru
        Start-Sleep -Milliseconds 1200
        if (-not $process.HasExited -or (Test-Path (Join-Path $LogsDir "ultima_ejecucion.txt"))) {
            Close-BootstrapWindow
            return
        }
    }

    throw "No se ha podido abrir la ventana del proceso automaticamente."
}

function Validate-ProjectFiles {
    $requiredPaths = @(
        $FlowScript,
        $RequirementsFile,
        (Join-Path $RepoRoot "01_Videos"),
        (Join-Path $RepoRoot "02_Transcripciones_por_llamada"),
        (Join-Path $RepoRoot "03_Texto_para_Copilot"),
        (Join-Path $RepoRoot "04_Videos_ya_procesados")
    )

    $missing = @()
    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path $requiredPath)) {
            $missing += $requiredPath
        }
    }

    if ($missing.Count -gt 0) {
        throw "La carpeta del proyecto no esta completa. Faltan estas rutas: $($missing -join '; ')"
    }
}

try {
    if (-not (Acquire-BootstrapLock)) {
        Show-AlreadyRunningNotice
        exit 90
    }

    Clear-VisibleDiagnostic
    Clear-BootstrapStatus
    Start-BootstrapWindow
    Write-Log "Inicio de preparacion de Windows."
    Write-Log "Runtime local del proyecto: $(Get-ProjectRuntimeRoot)"
    $script:SetupStage = "validando carpeta del proyecto"
    Update-BootstrapWindow -Status "Validando carpeta del proyecto" -Detail "Comprobando que el proyecto esta completo."
    Validate-ProjectFiles
    $script:SetupStage = "preparando entorno interno"
    Ensure-Venv
    $script:SetupStage = "preparando FFmpeg"
    Ensure-Ffmpeg
    if ($NoLaunch) {
        Close-BootstrapWindow
        Write-Log "Validacion completada sin lanzar el flujo."
    } else {
        $script:SetupStage = "iniciando el flujo"
        Start-Flow
    }
    $script:SetupStage = "completado"
    Write-Log "Preparacion completada."
} catch {
    $message = $_.Exception.Message
    $details = ($_ | Out-String)
    Write-Log "ERROR: $message"
    $summary = Get-FriendlySetupSummary -Message $message
    $report = Write-VisibleDiagnostic -Summary $summary -Details $details
    Close-BootstrapWindow
    Show-Error "$summary`n`nSe ha guardado un diagnostico en:`n$report"
    exit 1
} finally {
    Release-BootstrapLock
}
