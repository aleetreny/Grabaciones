Contexto del Proyecto - Transcriptor personal de audios para macOS

1. Objetivo

Este repositorio existe para transcribir audios y videos en local, de forma sencilla y personal:

- Un solo boton en Mac.
- Un archivo .txt por cada audio/video.
- Guardado incremental para no perder trabajo si el proceso se interrumpe.

2. Alcance actual

- Solo macOS.
- Sin componentes de Windows.
- Sin exportes para Copilot.
- Sin consolidado diario unico.

3. Flujo de uso

1) Poner archivos en 01_Audios_entrada
2) Ejecutar TRANSCRIBIR AUDIOS - macOS.command
3) Ver progreso en ventana
4) Recoger textos en 02_Transcripciones/YYYY-MM-DD
5) Los originales pasan a 03_Audios_procesados/YYYY-MM-DD

4. Decisiones tecnicas

- Motor de transcripcion: Whisper local.
- Modelo por defecto: turbo.
- Idioma por defecto: es.
- FFmpeg: preferencia por binario enlazado en _interno/herramientas/macos/ffmpeg y fallback al del sistema.

5. Requisitos funcionales clave

- Guardar cada .txt justo al terminar cada archivo.
- Mostrar progreso de lote y de archivo en tiempo real.
- Poder relanzar el flujo sin reprocesar lo ya movido a procesados.

6. Archivos principales

- _interno/bootstrap_macos.sh
- _interno/ejecutar_flujo.py
- _interno/pipeline.py
- TRANSCRIBIR AUDIOS - macOS.command
