#!/bin/bash
set -e

cd "$(dirname "$0")"
ROOT_DIR="$(pwd)"
MAC_BINARY="$ROOT_DIR/_interno/runtime/macos/iniciar_flujo"
MAC_VENV="$ROOT_DIR/_interno/venv-macos/bin/python3"
PYTHON_BIN=""

if [ -x "$MAC_BINARY" ]; then
  "$MAC_BINARY" >/dev/null 2>&1 &
  exit 0
fi

if [ -x "$MAC_VENV" ]; then
  PYTHON_BIN="$MAC_VENV"
else
  PYTHON_BIN="$(command -v python3 || true)"
fi

if [ -z "$PYTHON_BIN" ]; then
  osascript -e 'display alert "Procesar llamadas" message "No se ha encontrado Python 3 en este Mac." as critical'
  exit 1
fi

osascript <<APPLESCRIPT
do shell script "cd \"$ROOT_DIR\" && \"$PYTHON_BIN\" _interno/ejecutar_flujo.py >/dev/null 2>&1 &"
APPLESCRIPT
