# Procesador de llamadas

Esta carpeta esta preparada para que el uso diario sea muy simple.

## Uso normal

1. Copiar los videos o audios nuevos en `01_Videos`
2. Hacer doble clic en el boton de su sistema:
   - `INICIAR PROCESO - Windows`
   - `INICIAR PROCESO - macOS`
3. Esperar a que termine
4. Abrir el archivo final en `03_Texto_para_Copilot`
5. Subir ese `.txt` a Copilot

## Carpetas importantes

- `01_Videos`: entrada de archivos nuevos
- `02_Transcripciones_por_llamada`: historico de transcripciones individuales
- `03_Texto_para_Copilot`: salida final lista para Copilot
- `04_Videos_ya_procesados`: historico de videos ya usados

## Qué subir a GitHub

Este repo ya esta preparado para no subir basura local.

Se ignoran automaticamente:

- videos y audios de prueba
- transcripciones generadas
- archivos finales para Copilot
- videos ya procesados
- logs
- entornos virtuales
- el `ffmpeg.exe` grande de Windows

## Cómo dejarlo listo en un Mac

Haz esto en tu otro ordenador Mac dentro de la carpeta del proyecto:

1. Instala Homebrew si no lo tienes
2. Instala Python y FFmpeg:

```bash
brew install python ffmpeg
```

3. Crea el entorno local del Mac:

```bash
python3 -m venv _interno/venv-macos
source _interno/venv-macos/bin/activate
pip install -r _interno/requirements.txt
```

4. Da permiso de ejecucion al boton de Mac:

```bash
chmod +x "INICIAR PROCESO - macOS.command"
```

5. Prueba el flujo:
   - mete un video en `01_Videos`
   - haz doble clic en `INICIAR PROCESO - macOS.command`

## Primer arranque en Mac

- Si ese Mac nunca ha usado Whisper, la primera ejecucion puede tardar bastante mas
- En ese primer uso puede descargar el modelo `small`
- Lo normal es que despues las siguientes ejecuciones ya sean mas directas

## Si macOS bloquea el boton

La primera vez puede que macOS no deje abrirlo por seguridad. Si pasa:

1. Haz clic derecho sobre `INICIAR PROCESO - macOS.command`
2. Pulsa `Abrir`
3. Confirma la apertura

## Nota importante para Windows

El `ffmpeg.exe` de Windows no se sube al repo porque GitHub lo rechazara por tamaño.

En tu equipo actual sigue funcionando porque ya lo tienes localmente en:

- `_interno/herramientas/windows/ffmpeg.exe`

Si algun dia quieres compartir tambien la version Windows lista para usar desde GitHub, lo mejor es hacerlo en un `Release` o con Git LFS, no en el commit normal.
