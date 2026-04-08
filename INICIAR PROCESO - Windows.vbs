Option Explicit

Dim shell, fso, rootPath, runtimeExe, pythonwExe, pythonExe, scriptPath, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

rootPath = fso.GetParentFolderName(WScript.ScriptFullName)
runtimeExe = rootPath & "\_interno\runtime\windows\iniciar_flujo.exe"
pythonwExe = rootPath & "\_interno\venv\Scripts\pythonw.exe"
pythonExe = rootPath & "\_interno\venv\Scripts\python.exe"
scriptPath = rootPath & "\_interno\ejecutar_flujo.py"

If fso.FileExists(pythonwExe) Then
    command = """" & pythonwExe & """ """ & scriptPath & """"
    shell.Run command, 0, False
ElseIf fso.FileExists(pythonExe) Then
    command = """" & pythonExe & """ """ & scriptPath & """"
    shell.Run command, 0, False
ElseIf fso.FileExists(runtimeExe) Then
    shell.Run """" & runtimeExe & """", 0, False
Else
    MsgBox "No se ha encontrado el ejecutable de Windows ni un Python interno para lanzar el proceso.", vbExclamation, "Procesar llamadas"
End If
