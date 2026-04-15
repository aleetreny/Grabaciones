from __future__ import annotations

import importlib
import os
import shutil
import subprocess
import sys
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Callable

MEDIA_EXTENSIONS = {
    ".aac",
    ".aiff",
    ".flac",
    ".m4a",
    ".mkv",
    ".mov",
    ".mp3",
    ".mp4",
    ".ogg",
    ".opus",
    ".wav",
    ".webm",
}

DEFAULT_MODEL_NAME = os.environ.get("WHISPER_MODEL", "turbo")
DEFAULT_LANGUAGE = os.environ.get("WHISPER_LANGUAGE", "es")
ProgressCallback = Callable[[str, dict[str, object]], None]


class PipelineError(RuntimeError):
    pass


@dataclass(frozen=True)
class ProjectPaths:
    root: Path
    incoming_audios: Path
    transcriptions: Path
    processed_audios: Path
    internal_root: Path
    tools_root: Path

    def ensure_directories(self) -> None:
        for path in (
            self.incoming_audios,
            self.transcriptions,
            self.processed_audios,
            self.internal_root,
            self.tools_root,
        ):
            path.mkdir(parents=True, exist_ok=True)


@dataclass(frozen=True)
class RunSummary:
    processed_files: int
    transcript_folder: Path
    archive_folder: Path


def repository_root() -> Path:
    return Path(__file__).resolve().parents[1]


def project_paths(root: Path | None = None) -> ProjectPaths:
    base = root or repository_root()
    internal_root = base / "_interno"
    return ProjectPaths(
        root=base,
        incoming_audios=base / "01_Audios_entrada",
        transcriptions=base / "02_Transcripciones",
        processed_audios=base / "03_Audios_procesados",
        internal_root=internal_root,
        tools_root=internal_root / "herramientas",
    )


def open_in_file_browser(path: Path) -> None:
    target = str(path)
    if sys.platform == "darwin":
        subprocess.Popen(["open", target])
        return
    subprocess.Popen(["xdg-open", target])


def discover_media_files(folder: Path) -> list[Path]:
    return sorted(
        (
            path
            for path in folder.iterdir()
            if path.is_file() and path.suffix.lower() in MEDIA_EXTENSIONS
        ),
        key=lambda item: item.name.lower(),
    )


def clean_transcript_text(text: str) -> str:
    lines = [line.rstrip() for line in text.replace("\r\n", "\n").splitlines()]
    cleaned = "\n".join(lines).strip()
    return cleaned or "(Sin contenido reconocido)"


def unique_file_path(folder: Path, original_name: str) -> Path:
    candidate = folder / original_name
    if not candidate.exists():
        return candidate

    stem = Path(original_name).stem
    suffix = Path(original_name).suffix
    counter = 2
    while True:
        candidate = folder / f"{stem}_{counter}{suffix}"
        if not candidate.exists():
            return candidate
        counter += 1


def parse_creation_datetime(value: str) -> datetime | None:
    raw = value.strip()
    if not raw:
        return None

    normalized = raw.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        pass

    for fmt in (
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M:%S.%f",
    ):
        try:
            return datetime.strptime(raw, fmt)
        except ValueError:
            continue

    return None


def probe_media_creation_datetime(media_file: Path) -> datetime | None:
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format_tags=creation_time:stream_tags=creation_time",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(media_file),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return None

    if result.returncode != 0:
        return None

    for line in result.stdout.splitlines():
        parsed = parse_creation_datetime(line)
        if parsed is not None:
            return parsed

    return None


def file_system_creation_datetime(media_file: Path) -> datetime:
    stat_info = media_file.stat()
    timestamp = getattr(stat_info, "st_birthtime", stat_info.st_mtime)
    return datetime.fromtimestamp(timestamp)


def creation_date_label(media_file: Path, log: Callable[[str], None]) -> str:
    metadata_dt = probe_media_creation_datetime(media_file)
    if metadata_dt is not None:
        label = metadata_dt.strftime("%Y-%m-%d")
        log(f"Fecha metadata detectada para {media_file.name}: {label}")
        return label

    fallback_dt = file_system_creation_datetime(media_file)
    label = fallback_dt.strftime("%Y-%m-%d")
    log(f"Fecha de sistema usada para {media_file.name}: {label}")
    return label


def locate_ffmpeg(paths: ProjectPaths) -> Path | None:
    explicit = os.environ.get("FFMPEG_BINARY")
    if explicit and Path(explicit).exists():
        return Path(explicit)

    bundled = paths.tools_root / "macos" / "ffmpeg"
    if bundled.exists():
        return bundled

    system_ffmpeg = shutil.which("ffmpeg")
    return Path(system_ffmpeg) if system_ffmpeg else None


def configure_ffmpeg(paths: ProjectPaths, log: Callable[[str], None]) -> None:
    ffmpeg_path = locate_ffmpeg(paths)
    if ffmpeg_path is None:
        raise PipelineError(
            "No se ha encontrado FFmpeg. Revisa _interno/herramientas/macos o instala ffmpeg con Homebrew."
        )

    os.environ["PATH"] = f"{ffmpeg_path.parent}{os.pathsep}{os.environ.get('PATH', '')}"
    os.environ["FFMPEG_BINARY"] = str(ffmpeg_path)
    log(f"FFmpeg listo: {ffmpeg_path}")


def detect_torch_device(log: Callable[[str], None]) -> str:
    try:
        import torch

        if torch.cuda.is_available():
            return "cuda"
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
        return "cpu"
    except Exception:  # noqa: BLE001
        log("No se ha podido detectar aceleracion por hardware. Se usara CPU.")
        return "cpu"


def emit_progress(
    progress: ProgressCallback | None,
    event: str,
    **payload: object,
) -> None:
    if progress is not None:
        progress(event, payload)


def describe_model_load_error(error: Exception) -> str:
    message = str(error).strip()
    lowered = message.lower()

    if (
        ("no module named" in lowered and "whisper" in lowered)
        or ("modulenotfounderror" in lowered and "whisper" in lowered)
    ):
        return (
            "Whisper no se ha instalado correctamente todavia. "
            "Vuelve a pulsar el boton para completar la preparacion del entorno."
        )

    if any(
        token in lowered
        for token in (
            "ssl",
            "certificate",
            "urlopen",
            "download",
            "http error",
            "connection",
            "proxy",
            "timed out",
            "getaddrinfo",
            "nodename nor servname provided",
        )
    ):
        return (
            "No se ha podido descargar o cargar el modelo de Whisper. "
            "Comprueba internet y que la red no bloquee la descarga."
        )

    if "torch" in lowered:
        return (
            "Whisper no se ha podido cargar correctamente. "
            "Puede faltar alguna dependencia del entorno interno."
        )

    if message:
        return f"No se ha podido cargar Whisper. Detalle tecnico: {message}"
    return "No se ha podido cargar Whisper."


def describe_transcription_error(media_file: Path, error: Exception) -> str:
    message = str(error).strip()
    lowered = message.lower()

    if any(
        token in lowered
        for token in (
            "ffmpeg",
            "invalid data found",
            "could not find codec parameters",
            "moov atom not found",
            "error opening input",
        )
    ):
        return (
            f"No se ha podido leer el archivo {media_file.name}. "
            "Comprueba que el audio no este danado."
        )

    if any(token in lowered for token in ("permission", "denied")):
        return (
            f"No se ha podido acceder a {media_file.name}. "
            "Comprueba que el archivo no este abierto en otra app."
        )

    if any(token in lowered for token in ("cannot find the file", "no such file", "system cannot find")):
        return (
            f"No se ha encontrado {media_file.name} durante la transcripcion. "
            "Comprueba que siga dentro de 01_Audios_entrada."
        )

    if message:
        return f"No se ha podido transcribir {media_file.name}. Detalle tecnico: {message}"
    return f"No se ha podido transcribir {media_file.name}."


class WhisperTranscriber:
    def __init__(
        self,
        log: Callable[[str], None],
        model_name: str = DEFAULT_MODEL_NAME,
        language: str = DEFAULT_LANGUAGE,
        progress: ProgressCallback | None = None,
        device: str | None = None,
    ) -> None:
        self.log = log
        self.model_name = model_name
        self.language = language
        self.progress = progress
        self.device = device

        self._model = None
        self._device = "cpu"
        self.current_file = 0
        self.total_files = 0
        self.file_name = ""

    def set_file_context(self, current_file: int, total_files: int, file_name: str) -> None:
        self.current_file = current_file
        self.total_files = total_files
        self.file_name = file_name

    def emit_file_progress(self, current_value: int, total_value: int) -> None:
        safe_total = max(total_value, 1)
        percent = max(0, min(100, round(current_value * 100 / safe_total)))
        emit_progress(
            self.progress,
            "file_progress",
            current_file=self.current_file,
            total_files=self.total_files,
            file_name=self.file_name,
            current_value=current_value,
            total_value=safe_total,
            percent=percent,
        )

    @contextmanager
    def gui_progress_patch(self):
        transcribe_module = importlib.import_module("whisper.transcribe")
        original_tqdm = transcribe_module.tqdm.tqdm

        transcriber = self

        class QuietTqdm:
            def __init__(self, *args, total: int | None = None, disable: bool = False, **kwargs):
                self.total = total or 0
                self.disable = disable
                self.current = 0
                if not self.disable:
                    transcriber.emit_file_progress(0, self.total)

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                self.close()
                return False

            def update(self, value: int = 1) -> None:
                if self.disable:
                    return
                self.current += value
                transcriber.emit_file_progress(self.current, self.total)

            def close(self) -> None:
                if not self.disable:
                    transcriber.emit_file_progress(self.total, self.total)

        transcribe_module.tqdm.tqdm = QuietTqdm
        try:
            yield
        finally:
            transcribe_module.tqdm.tqdm = original_tqdm

    @property
    def model(self):
        if self._model is None:
            self._device = self.device or detect_torch_device(self.log)
            self.log(
                "Cargando Whisper "
                f"(modelo: {self.model_name}, idioma: {self.language}, dispositivo: {self._device})."
            )
            emit_progress(
                self.progress,
                "model_loading",
                model_name=self.model_name,
                language=self.language,
                device=self._device,
            )
            try:
                import whisper

                self._model = whisper.load_model(self.model_name, device=self._device)
            except Exception as error:  # noqa: BLE001
                raise PipelineError(describe_model_load_error(error)) from error
            emit_progress(
                self.progress,
                "model_ready",
                model_name=self.model_name,
                language=self.language,
                device=self._device,
            )
        return self._model

    def transcribe(self, media_file: Path) -> str:
        try:
            with self.gui_progress_patch():
                result = self.model.transcribe(
                    str(media_file),
                    task="transcribe",
                    language=self.language,
                    verbose=False,
                    fp16=self._device == "cuda",
                    temperature=0.0,
                    beam_size=1,
                    best_of=1,
                    condition_on_previous_text=False,
                )
        except PipelineError:
            raise
        except Exception as error:  # noqa: BLE001
            raise PipelineError(describe_transcription_error(media_file, error)) from error
        return str(result.get("text", ""))


def run_pipeline(
    paths: ProjectPaths,
    transcriber: WhisperTranscriber | None = None,
    run_date: date | None = None,
    log: Callable[[str], None] = print,
    progress: ProgressCallback | None = None,
) -> RunSummary:
    paths.ensure_directories()
    media_files = discover_media_files(paths.incoming_audios)

    if not media_files:
        raise PipelineError(
            "No hay audios nuevos en 01_Audios_entrada. Copia ahi tus archivos y vuelve a pulsar el boton."
        )

    day_label = (run_date or date.today()).isoformat()
    total_files = len(media_files)
    emit_progress(progress, "pipeline_started", total_files=total_files, day_label=day_label)

    transcript_folder = paths.transcriptions / day_label
    archive_folder = paths.processed_audios / day_label
    transcript_folder.mkdir(parents=True, exist_ok=True)
    archive_folder.mkdir(parents=True, exist_ok=True)

    active_transcriber = transcriber or WhisperTranscriber(log=log, progress=progress)
    if transcriber is None:
        configure_ffmpeg(paths, log)

    processed = 0
    for index, media_file in enumerate(media_files, start=1):
        if hasattr(active_transcriber, "set_file_context"):
            active_transcriber.set_file_context(index, total_files, media_file.name)

        emit_progress(
            progress,
            "file_started",
            current_file=index,
            total_files=total_files,
            file_name=media_file.name,
        )
        log(f"Transcribiendo ({index}/{total_files}): {media_file.name}")

        file_date_label = creation_date_label(media_file, log)
        transcript_name = f"{file_date_label} - {media_file.stem}.txt"
        transcript_path = unique_file_path(transcript_folder, transcript_name)
        transcript_text = clean_transcript_text(active_transcriber.transcribe(media_file))

        # Se guarda cada archivo antes de mover el audio para que el avance quede persistido.
        transcript_path.write_text(transcript_text + "\n", encoding="utf-8")
        log(f"Transcripcion guardada: {transcript_path.name}")

        archive_path = unique_file_path(archive_folder, media_file.name)
        shutil.move(str(media_file), archive_path)
        processed += 1
        log(f"Audio movido a procesados: {archive_path.name}")

        emit_progress(
            progress,
            "file_finished",
            current_file=index,
            total_files=total_files,
            file_name=media_file.name,
            transcript_name=transcript_path.name,
        )

    log("Proceso terminado correctamente.")
    emit_progress(
        progress,
        "pipeline_finished",
        processed_files=processed,
        total_files=total_files,
        transcript_folder=transcript_folder,
        archive_folder=archive_folder,
    )

    return RunSummary(
        processed_files=processed,
        transcript_folder=transcript_folder,
        archive_folder=archive_folder,
    )
