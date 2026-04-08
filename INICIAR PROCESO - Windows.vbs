Option Explicit

Dim shell, fso, rootPath, bootstrapScript, pythonwExe, pythonExe, ffmpegExe, scriptPath
Dim bootstrapCommand, command, exitCode
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

rootPath = fso.GetParentFolderName(WScript.ScriptFullName)
bootstrapScript = rootPath & "\_interno\bootstrap_windows.ps1"
pythonwExe = rootPath & "\_interno\venv\Scripts\pythonw.exe"
pythonExe = rootPath & "\_interno\venv\Scripts\python.exe"
ffmpegExe = rootPath & "\_interno\herramientas\windows\ffmpeg.exe"
scriptPath = rootPath & "\_interno\ejecutar_flujo.py"

shell.CurrentDirectory = rootPath

If fso.FileExists(scriptPath) And fso.FileExists(ffmpegExe) And (fso.FileExists(pythonwExe) Or fso.FileExists(pythonExe)) Then
    If fso.FileExists(pythonwExe) Then
        command = """" & pythonwExe & """ """ & scriptPath & """"
    Else
        command = """" & pythonExe & """ """ & scriptPath & """"
    End If
    shell.Run command, 0, False
ElseIf fso.FileExists(bootstrapScript) Then
    bootstrapCommand = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File """ & bootstrapScript & """ -NoLaunch"
    exitCode = shell.Run(bootstrapCommand, 0, True)

    If exitCode <> 0 Then
        MsgBox "No se ha podido preparar Windows automaticamente." & vbCrLf & vbCrLf & _
               "Revisa el log en:" & vbCrLf & rootPath & "\_interno\logs\instalacion_windows.log", vbExclamation, "Procesar llamadas"
    ElseIf fso.FileExists(pythonwExe) Then
        command = """" & pythonwExe & """ """ & scriptPath & """"
        shell.Run command, 0, False
    ElseIf fso.FileExists(pythonExe) Then
        command = """" & pythonExe & """ """ & scriptPath & """"
        shell.Run command, 0, False
    Else
        MsgBox "Windows se ha preparado, pero no se ha encontrado el lanzador interno." & vbCrLf & vbCrLf & _
               "Revisa el log en:" & vbCrLf & rootPath & "\_interno\logs\instalacion_windows.log", vbExclamation, "Procesar llamadas"
    End If
Else
    MsgBox "No se ha encontrado el preparador automatico de Windows.", vbExclamation, "Procesar llamadas"
End If
