#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(pwd)"
LOG_DIR="$ROOT_DIR/_interno/logs"
LOG_FILE="$LOG_DIR/instalacion_macos.log"
FLOW_LOG_FILE="$LOG_DIR/flujo_macos.log"
DIAGNOSTIC_FILE="$ROOT_DIR/DIAGNOSTICO - ultimo error.txt"
MAC_VENV_DIR="$ROOT_DIR/_interno/venv-macos"
MAC_PYTHON="$MAC_VENV_DIR/bin/python3"
MAC_FFMPEG_LINK="$ROOT_DIR/_interno/herramientas/macos/ffmpeg"
MAC_PYTHON_FORMULA="${MAC_PYTHON_FORMULA:-python@3.12}"
CURRENT_STAGE="inicio"

mkdir -p "$LOG_DIR" "$ROOT_DIR/_interno/herramientas/macos"
touch "$LOG_FILE"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1
export PYTHONUTF8=1

is_silent() {
  [[ "${TRANSCRIPCION_SILENCIOSA:-0}" == "1" ]]
}

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
  if is_silent; then
    return
  fi
  osascript -e "display dialog \"${message//\"/\\\"}\" with title \"Transcribir audios\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
}

clear_diagnostic() {
  rm -f "$DIAGNOSTIC_FILE"
}

summarize_failure() {
  local message="${1:-}"
  local lowered
  lowered="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]')"

  if [[ "$lowered" == *"curl"* || "$lowered" == *"download"* || "$lowered" == *"ssl"* || "$lowered" == *"certificate"* || "$lowered" == *"proxy"* || "$lowered" == *"connection"* || "$lowered" == *"pypi.org"* || "$lowered" == *"python.org"* || "$lowered" == *"githubusercontent"* ]]; then
    printf '%s\n' "No se ha podido descargar uno de los componentes necesarios. Comprueba internet o si la red bloquea la descarga."
    return
  fi

  if [[ "$lowered" == *"permission denied"* || "$lowered" == *"operation not permitted"* ]]; then
    printf '%s\n' "macOS ha bloqueado parte de la preparacion automatica. Comprueba permisos y vuelve a intentarlo."
    return
  fi

  if [[ "$lowered" == *"brew"* || "$CURRENT_STAGE" == *"Homebrew"* ]]; then
    printf '%s\n' "No se ha podido preparar Homebrew automaticamente en este Mac."
    return
  fi

  if [[ "$lowered" == *"ffmpeg"* || "$CURRENT_STAGE" == *"FFmpeg"* ]]; then
    printf '%s\n' "No se ha podido preparar FFmpeg automaticamente en este Mac."
    return
  fi

  if [[ "$lowered" == *"python"* || "$lowered" == *"whisper"* || "$lowered" == *"torch"* || "$CURRENT_STAGE" == *"Python"* || "$CURRENT_STAGE" == *"dependencias"* ]]; then
    printf '%s\n' "No se ha podido preparar Python o las dependencias internas en este Mac."
    return
  fi

  printf '%s\n' "No se ha podido preparar este Mac automaticamente."
}

write_diagnostic() {
  local summary="$1"
  local details="$2"
  local log_contents=""

  if [ -f "$LOG_FILE" ]; then
    log_contents="$(cat "$LOG_FILE")"
  fi

  cat >"$DIAGNOSTIC_FILE" <<EOF
DIAGNOSTICO DEL ULTIMO ERROR

Fecha: $(date '+%Y-%m-%d %H:%M:%S')
Paso del preparador: $CURRENT_STAGE
Carpeta del proyecto: $ROOT_DIR
Log de instalacion: $LOG_FILE

RESUMEN
$summary

LOG DE INSTALACION
${log_contents:-"(Sin contenido)"}

DETALLE TECNICO
${details:-"(Sin detalle)"}
EOF
}

fail_with_diagnostic() {
  local summary="$1"
  local details="$2"

  write_diagnostic "$summary" "$details"
  open "$DIAGNOSTIC_FILE" >/dev/null 2>&1 || true
  show_dialog "$summary"$'\n\n'"Se ha guardado un diagnostico en:"$'\n'"$DIAGNOSTIC_FILE"
  exit 1
}

handle_unexpected_error() {
  local line="$1"
  local command="$2"
  local details="Linea: $line
Comando: $command"
  local summary
  summary="$(summarize_failure "$command")"
  trap - ERR
  fail_with_diagnostic "$summary" "$details"
}

trap 'handle_unexpected_error "$LINENO" "$BASH_COMMAND"' ERR

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

  CURRENT_STAGE="herramientas base de Apple"
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

  CURRENT_STAGE="instalando Homebrew"
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

  CURRENT_STAGE="instalando $package_name"
  log "Instalando paquete: $package_name"
  if run_and_log brew install "$package_name"; then
    return
  fi

  if brew list --versions "$package_name" >/dev/null 2>&1; then
    log "Homebrew ha informado un conflicto al enlazar $package_name, pero el paquete ha quedado instalado. Continuo usando su ruta interna."
    return
  fi

  log "No se ha podido instalar el paquete: $package_name"
  fail_with_diagnostic "No se ha podido instalar $package_name automaticamente en este Mac." "Paquete: $package_name"
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
  CURRENT_STAGE="localizando Python"
  system_python="$(resolve_brew_binary "$MAC_PYTHON_FORMULA" python3 || command -v python3 || true)"
  if [ -z "$system_python" ]; then
    log "No se ha encontrado python3 despues de instalarlo."
    fail_with_diagnostic "No se ha podido encontrar Python 3 en este Mac." "No se encontro python3 despues de preparar Homebrew y Python."
  fi

  log "Python seleccionado: $system_python"

  if [ ! -x "$MAC_PYTHON" ]; then
    CURRENT_STAGE="creando entorno interno"
    log "Creando entorno interno del Mac."
    "$system_python" -m venv "$MAC_VENV_DIR"
  fi

  CURRENT_STAGE="actualizando herramientas base de Python"
  log "Actualizando herramientas basicas de Python."
  if ! run_and_log "$MAC_PYTHON" -m pip install --upgrade pip setuptools wheel; then
    fail_with_diagnostic "No se han podido actualizar las herramientas base de Python en este Mac." "Ha fallado pip install --upgrade pip setuptools wheel"
  fi

  if ! "$MAC_PYTHON" -c "import whisper" >/dev/null 2>&1; then
    CURRENT_STAGE="instalando dependencias internas"
    log "Instalando dependencias de la aplicacion."
    if ! run_and_log "$MAC_PYTHON" -m pip install -r "$ROOT_DIR/_interno/requirements.txt"; then
      fail_with_diagnostic "No se han podido instalar las dependencias internas de la aplicacion en este Mac." "Ha fallado pip install -r _interno/requirements.txt"
    fi
  else
    log "Las dependencias principales ya estaban instaladas."
  fi
}

launch_flow() {
  CURRENT_STAGE="iniciando el flujo"
  log "Arrancando flujo de transcripcion."
  : > "$FLOW_LOG_FILE"

  export WHISPER_MODEL="${WHISPER_MODEL:-turbo}"
  export WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-es}"

  "$MAC_PYTHON" "$ROOT_DIR/_interno/ejecutar_flujo.py" 2>&1 | tee -a "$FLOW_LOG_FILE"
  local flow_status=${PIPESTATUS[0]}
  return "$flow_status"
}

clear_diagnostic
log "Inicio de preparacion del Mac."
ensure_apple_tools
ensure_homebrew
ensure_python_and_ffmpeg
ensure_runtime
launch_flow
CURRENT_STAGE="completado"
log "Proceso completado. Ya puedes cerrar esta ventana."
