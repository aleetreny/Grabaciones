Option Explicit

Dim shell, fso, rootPath, bootstrapScript, scriptPath, diagnosticPath
Dim bootstrapCommand, exitCode
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

rootPath = fso.GetParentFolderName(WScript.ScriptFullName)
bootstrapScript = rootPath & "\_interno\bootstrap_windows.ps1"
scriptPath = rootPath & "\_interno\ejecutar_flujo.py"
diagnosticPath = rootPath & "\DIAGNOSTICO - ultimo error.txt"

shell.CurrentDirectory = rootPath

Sub ClearDiagnostic()
    On Error Resume Next
    If fso.FileExists(diagnosticPath) Then
        fso.DeleteFile diagnosticPath, True
    End If
    On Error GoTo 0
End Sub

Sub WriteDiagnostic(summary, details)
    Dim report
    Set report = fso.CreateTextFile(diagnosticPath, True, True)
    report.WriteLine "DIAGNOSTICO DEL ULTIMO ERROR"
    report.WriteLine ""
    report.WriteLine "Fecha: " & Now
    report.WriteLine "Carpeta del proyecto: " & rootPath
    report.WriteLine ""
    report.WriteLine "RESUMEN"
    report.WriteLine summary
    report.WriteLine ""
    report.WriteLine "DETALLE"
    report.WriteLine details
    report.Close
End Sub

Sub OpenDiagnostic()
    If fso.FileExists(diagnosticPath) Then
        shell.Run "notepad.exe """ & diagnosticPath & """", 1, False
    End If
End Sub

Sub ShowFailure(summary, details)
    WriteDiagnostic summary, details
    OpenDiagnostic
    MsgBox summary & vbCrLf & vbCrLf & "Se ha abierto este diagnostico:" & vbCrLf & diagnosticPath, vbExclamation, "Procesar llamadas"
End Sub

ClearDiagnostic

If Not fso.FileExists(scriptPath) Then
    ShowFailure "La carpeta del proyecto no esta completa o se esta ejecutando desde un zip.", _
                "No se ha encontrado el archivo interno:" & vbCrLf & scriptPath & vbCrLf & vbCrLf & _
                "Extrae la carpeta completa y vuelve a intentarlo."
ElseIf fso.FileExists(bootstrapScript) Then
    bootstrapCommand = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File """ & bootstrapScript & """"
    exitCode = shell.Run(bootstrapCommand, 0, True)

    If exitCode = 90 Then
        ' Ya hay otra preparacion o ejecucion en marcha. El propio bootstrap ya ha avisado al usuario.
    ElseIf exitCode <> 0 Then
        If fso.FileExists(diagnosticPath) Then
            OpenDiagnostic
            MsgBox "No se ha podido preparar Windows automaticamente." & vbCrLf & vbCrLf & _
                   "Se ha abierto este diagnostico:" & vbCrLf & diagnosticPath, vbExclamation, "Procesar llamadas"
        Else
            ShowFailure "No se ha podido preparar Windows automaticamente.", _
                        "No se ha generado el diagnostico automatico." & vbCrLf & _
                        "Revisa si el proyecto esta completo y vuelve a intentarlo."
        End If
    End If
Else
    ShowFailure "No se ha encontrado el preparador automatico de Windows.", _
                "Falta este archivo:" & vbCrLf & bootstrapScript & vbCrLf & vbCrLf & _
                "Comprueba que la carpeta del proyecto este completa."
End If
