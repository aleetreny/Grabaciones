# Procesador de llamadas

Esta carpeta esta pensada para que el uso diario sea solo de doble clic.

## Uso normal

1. Copia los videos o audios nuevos en `01_Videos`.
2. Haz doble clic en el boton de tu sistema:
   - `INICIAR PROCESO - Windows.vbs`
   - `INICIAR PROCESO - macOS.command`
3. Espera a que termine el proceso.
4. Abre el archivo final que aparece en `03_Texto_para_Copilot`.
5. Sube ese `.txt` a Copilot.

## Carpetas importantes

- `01_Videos`: entrada de archivos nuevos.
- `02_Transcripciones_por_llamada`: historico de transcripciones por llamada.
- `03_Texto_para_Copilot`: salida final lista para Copilot.
- `04_Videos_ya_procesados`: historico de videos ya usados.

## Windows totalmente automatico

En Windows, el boton prepara el equipo automaticamente la primera vez si hace falta.

Al hacer doble clic en `INICIAR PROCESO - Windows.vbs`, el sistema intentara:

- localizar o instalar Python 3;
- localizar o instalar FFmpeg;
- crear el entorno interno del proyecto;
- instalar Whisper y las dependencias necesarias;
- lanzar el flujo normal con su ventana de progreso.

En la gran mayoria de equipos Windows 10 y 11 esto deberia bastar. Si un equipo no trae `winget`, el propio proceso avisara para instalar `App Installer` una vez y volver a pulsar el boton.

## macOS totalmente automatico

En macOS, el boton tambien prepara el equipo automaticamente la primera vez.

Al hacer doble clic en `INICIAR PROCESO - macOS.command`, el sistema intentara:

- instalar las herramientas base de Apple si faltan;
- instalar Homebrew si falta;
- instalar Python 3 si falta;
- instalar FFmpeg si falta;
- crear el entorno interno del proyecto;
- instalar Whisper y las dependencias necesarias;
- lanzar el flujo normal.

## Lo normal en el primer arranque

En un equipo completamente limpio, la primera ejecucion puede tardar bastante mas que las siguientes.

Es normal que el sistema pida alguna confirmacion:

- en Windows, permisos de instalacion o avisos de `winget`;
- en macOS, apertura del `.command`, herramientas de Apple o contrasena del equipo.

Eso no se puede evitar del todo porque depende del sistema operativo, pero la idea sigue siendo la misma:

1. la persona hace doble clic en el boton;
2. acepta los avisos del sistema si aparecen;
3. el proyecto se prepara solo;
4. a partir de ahi, las siguientes ejecuciones son mucho mas directas.

## Si algo falla

Revisa estos archivos:

- `_interno/logs/ultima_ejecucion.txt`
- `_interno/logs/instalacion_windows.log`
- `_interno/logs/instalacion_macos.log`

## Que subir a GitHub

El repo ya esta preparado para no subir basura local.

Se ignoran automaticamente:

- videos y audios de trabajo;
- transcripciones generadas;
- archivos finales para Copilot;
- videos ya procesados;
- logs;
- entornos virtuales;
- binarios locales grandes como `ffmpeg.exe`.

## Prueba recomendada en otro equipo

1. clona el repo;
2. mete un video en `01_Videos`;
3. haz doble clic en el boton del sistema;
4. deja que termine la preparacion inicial si es la primera vez;
5. comprueba que aparece el `.txt` final en `03_Texto_para_Copilot`.
