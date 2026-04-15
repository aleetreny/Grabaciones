# Transcriptor personal de audios (macOS)

Este proyecto esta preparado para un uso personal en Mac:

- Metes audios en una carpeta.
- Pulsas un unico boton.
- Obtienes un `.txt` por cada audio.
- Cada transcripcion se guarda en cuanto termina cada archivo, para no perder avance si algo falla.

## Como usarlo

1. Copia los audios o videos nuevos en `01_Audios_entrada`.
2. Haz doble clic en `TRANSCRIBIR AUDIOS - macOS.command`.
3. Veras una ventana con progreso en tiempo real.
	Si por algun motivo no aparece la ventana grafica, veras una barra de progreso en la terminal.
4. Al terminar, las transcripciones se guardan en `02_Transcripciones/<YYYY-MM-DD>/`.
5. Los audios ya procesados se mueven a `03_Audios_procesados/<YYYY-MM-DD>/`.

## Que hace el flujo

- Usa Whisper en local.
- Modelo por defecto: `turbo` (alto rendimiento y buena calidad).
- Idioma por defecto: `es`.
- Guarda un `.txt` individual por archivo de audio/video.
- El nombre del `.txt` incluye la fecha de creacion detectada + el nombre original: `YYYY-MM-DD - nombre_original.txt`.
- No genera archivo consolidado y no usa Copilot.

## Carpetas

- `01_Audios_entrada`: entrada de audios/videos pendientes.
- `02_Transcripciones`: salida de `.txt` individuales por fecha.
- `03_Audios_procesados`: audios/videos ya procesados por fecha.

## Si algo falla

- Se crea `DIAGNOSTICO - ultimo error.txt` en la raiz.
- Log tecnico: `_interno/logs/ultima_ejecucion.txt`.

## Repetir o re-procesar

- Para procesar nuevos audios: mete archivos en `01_Audios_entrada` y vuelve a pulsar el boton.
- Para re-procesar un audio ya usado: mueve ese archivo desde `03_Audios_procesados/<fecha>/` a `01_Audios_entrada`.

## Variables opcionales

- `WHISPER_MODEL`: cambia el modelo de Whisper (por defecto `turbo`; para maxima precision puedes usar `large-v3`).
- `WHISPER_LANGUAGE`: idioma de transcripcion (por defecto `es`).
- `TRANSCRIPCION_SILENCIOSA=1`: modo sin dialogs para ejecucion por terminal.
