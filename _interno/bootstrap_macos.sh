#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"
LOG_DIR="$ROOT_DIR/_interno/logs"
LOG_FILE="$LOG_DIR/instalacion_macos.log"
FLOW_LOG_FILE="$LOG_DIR/flujo_macos.log"
MAC_VENV_DIR="$ROOT_DIR/_interno/venv-macos"
MAC_PYTHON="$MAC_VENV_DIR/bin/python3"
MAC_FFMPEG_LINK="$ROOT_DIR/_interno/herramientas/macos/ffmpeg"
MAC_PYTHON_FORMULA="${MAC_PYTHON_FORMULA:-python@3.12}"

mkdir -p "$LOG_DIR" "$ROOT_DIR/_interno/herramientas/macos"
touch "$LOG_FILE"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1

log() {
  local message="$1"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" | tee -a "$LOG_FILE"
}

run_and_log() {
  "$@" 2>&1 | tee -a "$LOG_FILE"
  local status=${PIPESTATUS[0]}
  return "$status"
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
  if brew list --versions "$package_name" >/dev/null 2>&1; then
    log "Paquete ya disponible: $package_name"
    return
  fi

  log "Instalando paquete: $package_name"
  if run_and_log brew install "$package_name"; then
    return
  fi

  if brew list --versions "$package_name" >/dev/null 2>&1; then
    log "Homebrew ha informado un conflicto al enlazar $package_name, pero el paquete ha quedado instalado. Continuo usando su ruta interna."
    return
  fi

  log "No se ha podido instalar el paquete: $package_name"
  show_dialog "No se ha podido instalar $package_name. Revisa el log en _interno/logs/instalacion_macos.log"
  exit 1
}

resolve_brew_binary() {
  local formula_name="$1"
  local binary_name="$2"
  local formula_prefix
  formula_prefix="$(brew --prefix "$formula_name" 2>/dev/null || true)"
  if [ -z "$formula_prefix" ]; then
    return 1
  fi

  local candidate
  for candidate in \
    "$formula_prefix/bin/$binary_name" \
    "$formula_prefix/libexec/bin/$binary_name"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_python_and_ffmpeg() {
  ensure_brew_package "$MAC_PYTHON_FORMULA"
  ensure_brew_package ffmpeg

  local ffmpeg_bin
  ffmpeg_bin="$(resolve_brew_binary ffmpeg ffmpeg || command -v ffmpeg || true)"
  if [ -n "$ffmpeg_bin" ]; then
    ln -sf "$ffmpeg_bin" "$MAC_FFMPEG_LINK"
  fi
}

ensure_runtime() {
  local system_python
  system_python="$(resolve_brew_binary "$MAC_PYTHON_FORMULA" python3 || command -v python3 || true)"
  if [ -z "$system_python" ]; then
    log "No se ha encontrado python3 despues de instalarlo."
    show_dialog "No se ha podido encontrar Python 3 en este Mac."
    exit 1
  fi

  log "Python seleccionado: $system_python"

  if [ ! -x "$MAC_PYTHON" ]; then
    log "Creando entorno interno del Mac."
    "$system_python" -m venv "$MAC_VENV_DIR"
  fi

  log "Actualizando herramientas basicas de Python."
  if ! run_and_log "$MAC_PYTHON" -m pip install --upgrade pip setuptools wheel; then
    show_dialog "No se han podido actualizar las herramientas base de Python. Revisa el log en _interno/logs/instalacion_macos.log"
    exit 1
  fi

  if ! "$MAC_PYTHON" -c "import whisper" >/dev/null 2>&1; then
    log "Instalando dependencias de la aplicacion."
    if ! run_and_log "$MAC_PYTHON" -m pip install -r "$ROOT_DIR/_interno/requirements.txt"; then
      show_dialog "No se han podido instalar las dependencias de la aplicacion. Revisa el log en _interno/logs/instalacion_macos.log"
      exit 1
    fi
  else
    log "Las dependencias principales ya estaban instaladas."
  fi
}

launch_flow() {
  log "Arrancando flujo de procesamiento."
  : > "$FLOW_LOG_FILE"
  "$MAC_PYTHON" "$ROOT_DIR/_interno/ejecutar_flujo.py" >>"$FLOW_LOG_FILE" 2>&1
}

log "Inicio de preparacion del Mac."
ensure_apple_tools
ensure_homebrew
ensure_python_and_ffmpeg
ensure_runtime
launch_flow
log "Proceso completado. Ya puedes cerrar esta ventana."
