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

## macOS totalmente automatico

En Mac ya no hace falta preparar nada a mano.

La primera vez que esa persona haga doble clic en `INICIAR PROCESO - macOS.command`, el propio boton intentara:

- instalar las herramientas base de Apple si faltan
- instalar Homebrew si falta
- instalar Python 3 si falta
- instalar FFmpeg si falta
- crear el entorno interno del proyecto
- instalar Whisper y el resto de dependencias
- lanzar el flujo

## Lo normal en el primer arranque de Mac

En un Mac completamente limpio, el primer arranque puede pedir alguna accion del sistema:

- confirmacion de apertura del `.command`
- instalacion de las herramientas base de Apple
- contraseña del Mac para Homebrew

Eso no lo podemos saltar por completo porque lo controla Apple, pero la idea sigue siendo la misma:

1. la persona pulsa el boton
2. acepta lo que le pida macOS si sale algun aviso
3. el proyecto se termina de preparar solo
4. a partir de ahi, los siguientes usos ya son directos

## Primer arranque en Mac: tiempos

- Si ese Mac nunca ha usado Whisper, la primera ejecucion puede tardar bastante mas
- En ese primer uso puede descargar el modelo `small`
- La instalacion inicial de Homebrew, Python y FFmpeg tambien puede tardar varios minutos
- Despues las siguientes ejecuciones ya seran mucho mas directas

## Si macOS bloquea el boton

La primera vez puede que macOS no deje abrirlo por seguridad. Si pasa:

1. Haz clic derecho sobre `INICIAR PROCESO - macOS.command`
2. Pulsa `Abrir`
3. Confirma la apertura

## Recomendacion para probar en tu otro Mac

La prueba buena es esta:

1. clonar el repo en el Mac
2. meter un video en `01_Videos`
3. hacer doble clic en `INICIAR PROCESO - macOS.command`
4. dejar que el propio boton prepare ese Mac
5. comprobar que aparece el texto final en `03_Texto_para_Copilot`

## Nota importante para Windows

El `ffmpeg.exe` de Windows no se sube al repo porque GitHub lo rechazara por tamaño.

En tu equipo actual sigue funcionando porque ya lo tienes localmente en:

- `_interno/herramientas/windows/ffmpeg.exe`

Si algun dia quieres compartir tambien la version Windows lista para usar desde GitHub, lo mejor es hacerlo en un `Release` o con Git LFS, no en el commit normal.
