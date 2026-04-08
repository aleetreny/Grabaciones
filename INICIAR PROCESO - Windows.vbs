Option Explicit

Dim shell, fso, rootPath, bootstrapScript, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

rootPath = fso.GetParentFolderName(WScript.ScriptFullName)
bootstrapScript = rootPath & "\_interno\bootstrap_windows.ps1"

If fso.FileExists(bootstrapScript) Then
    command = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File """ & bootstrapScript & """"
    shell.Run command, 0, False
Else
    MsgBox "No se ha encontrado el preparador automatico de Windows.", vbExclamation, "Procesar llamadas"
End If
