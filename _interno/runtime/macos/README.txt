Si quieres un runtime nativo para macOS, generarlo debe hacerse desde un Mac.

En este repositorio, el arranque principal es:

TRANSCRIBIR AUDIOS - macOS.command

Ese launcher llama a _interno/bootstrap_macos.sh y luego ejecuta _interno/ejecutar_flujo.py
con el entorno interno preparado.
