#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"
LOG_DIR="$ROOT_DIR/_interno/logs"
LOG_FILE="$LOG_DIR/instalacion_macos.log"
MAC_VENV_DIR="$ROOT_DIR/_interno/venv-macos"
MAC_PYTHON="$MAC_VENV_DIR/bin/python3"
MAC_FFMPEG_LINK="$ROOT_DIR/_interno/herramientas/macos/ffmpeg"

mkdir -p "$LOG_DIR" "$ROOT_DIR/_interno/herramientas/macos"
touch "$LOG_FILE"

log() {
  local message="$1"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" | tee -a "$LOG_FILE"
}

show_dialog() {
  local message="$1"
  osascript -e "display dialog \"${message//\"/\\\"}\" with title \"Procesar llamadas\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
}

setup_brew_env() {
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_apple_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    return
  fi

  log "Faltan las herramientas base de Apple. Voy a pedirlas al sistema."
  show_dialog "macOS necesita instalar primero las herramientas base de Apple. Se abrira el asistente del sistema. Cuando termine, vuelve a pulsar el boton."
  xcode-select --install >/dev/null 2>&1 || true
  exit 1
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    setup_brew_env
    return
  fi

  log "Instalando Homebrew por primera vez."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  setup_brew_env
}

ensure_brew_package() {
  local package_name="$1"
  if brew list "$package_name" >/dev/null 2>&1; then
    log "Paquete ya disponible: $package_name"
    return
  fi

  log "Instalando paquete: $package_name"
  brew install "$package_name"
}

ensure_python_and_ffmpeg() {
  ensure_brew_package python
  ensure_brew_package ffmpeg

  local ffmpeg_bin
  ffmpeg_bin="$(command -v ffmpeg || true)"
  if [ -n "$ffmpeg_bin" ]; then
    ln -sf "$ffmpeg_bin" "$MAC_FFMPEG_LINK"
  fi
}

ensure_runtime() {
  local system_python
  system_python="$(command -v python3 || true)"
  if [ -z "$system_python" ]; then
    log "No se ha encontrado python3 despues de instalarlo."
    show_dialog "No se ha podido encontrar Python 3 en este Mac."
    exit 1
  fi

  if [ ! -x "$MAC_PYTHON" ]; then
    log "Creando entorno interno del Mac."
    "$system_python" -m venv "$MAC_VENV_DIR"
  fi

  log "Actualizando herramientas basicas de Python."
  "$MAC_PYTHON" -m pip install --upgrade pip setuptools wheel

  if ! "$MAC_PYTHON" -c "import whisper" >/dev/null 2>&1; then
    log "Instalando dependencias de la aplicacion."
    "$MAC_PYTHON" -m pip install -r "$ROOT_DIR/_interno/requirements.txt"
  else
    log "Las dependencias principales ya estaban instaladas."
  fi
}

launch_flow() {
  log "Arrancando flujo de procesamiento."
  "$MAC_PYTHON" "$ROOT_DIR/_interno/ejecutar_flujo.py" >/dev/null 2>&1 &
  disown || true
}

log "Inicio de preparacion del Mac."
ensure_apple_tools
ensure_homebrew
ensure_python_and_ffmpeg
ensure_runtime
launch_flow
log "Preparacion completada. Ya puedes cerrar esta ventana."
