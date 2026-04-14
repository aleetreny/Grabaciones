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
from typing import Callable, Iterable

MEDIA_EXTENSIONS = {
    ".aac",
    ".m4a",
    ".mkv",
    ".mov",
    ".mp3",
    ".mp4",
    ".wav",
    ".webm",
}

DEFAULT_MODEL_NAME = "small"
ProgressCallback = Callable[[str, dict[str, object]], None]


class PipelineError(RuntimeError):
    pass


@dataclass(frozen=True)
class ProjectPaths:
    root: Path
    incoming_videos: Path
    individual_transcripts: Path
    copilot_exports: Path
    processed_videos: Path
    internal_root: Path
    tools_root: Path

    def ensure_directories(self) -> None:
        for path in (
            self.incoming_videos,
            self.individual_transcripts,
            self.copilot_exports,
            self.processed_videos,
            self.internal_root,
            self.tools_root,
        ):
            path.mkdir(parents=True, exist_ok=True)


@dataclass(frozen=True)
class RunSummary:
    processed_files: int
    transcript_folder: Path
    archive_folder: Path
    export_file: Path


def repository_root() -> Path:
    return Path(__file__).resolve().parents[1]


def project_paths(root: Path | None = None) -> ProjectPaths:
    base = root or repository_root()
    internal_root = base / "_interno"
    return ProjectPaths(
        root=base,
        incoming_videos=base / "01_Videos",
        individual_transcripts=base / "02_Transcripciones_por_llamada",
        copilot_exports=base / "03_Texto_para_Copilot",
        processed_videos=base / "04_Videos_ya_procesados",
        internal_root=internal_root,
        tools_root=internal_root / "herramientas",
    )


def open_in_file_browser(path: Path) -> None:
    target = str(path)
    if sys.platform.startswith("win"):
        os.startfile(target)  # type: ignore[attr-defined]
        return
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


def locate_ffmpeg(paths: ProjectPaths) -> Path | None:
    explicit = os.environ.get("FFMPEG_BINARY")
    if explicit and Path(explicit).exists():
        return Path(explicit)

    candidates = []
    if sys.platform.startswith("win"):
        candidates.append(paths.tools_root / "windows" / "ffmpeg.exe")
    elif sys.platform == "darwin":
        candidates.append(paths.tools_root / "macos" / "ffmpeg")

    for candidate in candidates:
        if candidate.exists():
            return candidate

    system_ffmpeg = shutil.which("ffmpeg")
    return Path(system_ffmpeg) if system_ffmpeg else None


def configure_ffmpeg(paths: ProjectPaths, log: Callable[[str], None]) -> None:
    ffmpeg_path = locate_ffmpeg(paths)
    if ffmpeg_path is None:
        raise PipelineError(
            "No se ha encontrado FFmpeg. Revisa _interno/herramientas o instala ffmpeg en el equipo."
        )

    os.environ["PATH"] = f"{ffmpeg_path.parent}{os.pathsep}{os.environ.get('PATH', '')}"
    os.environ["FFMPEG_BINARY"] = str(ffmpeg_path)
    log(f"FFmpeg listo: {ffmpeg_path}")


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
            "Whisper no se ha instalado correctamente en este equipo todavia. "
            "Vuelve a pulsar el boton para que Windows termine de preparar el entorno interno."
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
            "407",
            "timed out",
            "name or service not known",
            "getaddrinfo",
            "nodename nor servname provided",
        )
    ):
        return (
            "No se ha podido descargar o cargar el modelo de Whisper en este equipo. "
            "Comprueba que tenga internet y que la red no bloquee la descarga."
        )

    if "torch" in lowered or "dll" in lowered:
        return (
            "Whisper no se ha podido cargar correctamente en este equipo. "
            "Puede faltar alguna dependencia del entorno interno."
        )

    if message:
        return f"No se ha podido cargar Whisper. Detalle tecnico: {message}"
    return "No se ha podido cargar Whisper en este equipo."


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
            "Comprueba que el video o audio no este danado."
        )

    if any(token in lowered for token in ("permission", "denied", "winerror 5", "winerror 32")):
        return (
            f"No se ha podido acceder a {media_file.name}. "
            "Comprueba que el archivo no este abierto en otro programa."
        )

    if any(token in lowered for token in ("cannot find the file", "no such file", "system cannot find")):
        return (
            f"No se ha encontrado el archivo {media_file.name} cuando se iba a transcribir. "
            "Comprueba que siga estando dentro de 01_Videos."
        )

    if message:
        return f"No se ha podido transcribir {media_file.name}. Detalle tecnico: {message}"
    return f"No se ha podido transcribir {media_file.name}."


class WhisperTranscriber:
    def __init__(
        self,
        log: Callable[[str], None],
        model_name: str = DEFAULT_MODEL_NAME,
        progress: ProgressCallback | None = None,
    ) -> None:
        self.log = log
        self.model_name = model_name
        self.progress = progress
        self._model = None
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
            self.log("Cargando el modelo de Whisper. Esto puede tardar un poco la primera vez.")
            emit_progress(self.progress, "model_loading", model_name=self.model_name)
            try:
                import whisper
                self._model = whisper.load_model(self.model_name)
            except Exception as error:  # noqa: BLE001
                raise PipelineError(describe_model_load_error(error)) from error
            emit_progress(self.progress, "model_ready", model_name=self.model_name)
        return self._model

    def transcribe(self, media_file: Path) -> str:
        try:
            with self.gui_progress_patch():
                result = self.model.transcribe(str(media_file), task="transcribe", verbose=False)
        except PipelineError:
            raise
        except Exception as error:  # noqa: BLE001
            raise PipelineError(describe_transcription_error(media_file, error)) from error
        return str(result.get("text", ""))


def build_daily_export(
    transcript_files: Iterable[Path],
    export_file: Path,
    day_label: str,
) -> Path:
    ordered = sorted(transcript_files, key=lambda item: item.name.lower())
    if not ordered:
        raise PipelineError("No hay transcripciones para consolidar en el archivo final.")

    sections = [
        "RESUMEN DEL LOTE",
        f"Fecha: {day_label}",
        f"Total de llamadas: {len(ordered)}",
        "",
        "INICIO DE TRANSCRIPCIONES",
        "",
    ]

    for index, transcript_file in enumerate(ordered, start=1):
        transcript_text = clean_transcript_text(transcript_file.read_text(encoding="utf-8"))
        sections.extend(
            [
                "=" * 72,
                f"LLAMADA {index:03d}",
                f"Archivo de audio o video: {transcript_file.stem}",
                f"Transcripcion: {transcript_file.name}",
                "=" * 72,
                "",
                transcript_text,
                "",
            ]
        )

    export_file.write_text("\n".join(sections).strip() + "\n", encoding="utf-8")
    return export_file


def rebuild_export_for_day(
    paths: ProjectPaths,
    day_label: str,
    generated_at: datetime | None = None,
    log: Callable[[str], None] = print,
) -> Path:
    transcript_day_folder = paths.individual_transcripts / day_label
    if not transcript_day_folder.exists():
        raise PipelineError(
            f"No existe la carpeta de transcripciones del dia {day_label}: {transcript_day_folder}"
        )

    transcript_files = sorted(transcript_day_folder.glob("*.txt"))
    timestamp = (generated_at or datetime.now()).strftime("%Y-%m-%d %H-%M-%S")
    export_file = paths.copilot_exports / f"{timestamp} - Texto para Copilot.txt"
    result = build_daily_export(transcript_files, export_file, day_label)
    log(f"Archivo consolidado actualizado: {result}")
    return result


def run_pipeline(
    paths: ProjectPaths,
    transcriber: WhisperTranscriber | None = None,
    run_date: date | None = None,
    log: Callable[[str], None] = print,
    progress: ProgressCallback | None = None,
) -> RunSummary:
    paths.ensure_directories()
    media_files = discover_media_files(paths.incoming_videos)

    if not media_files:
        raise PipelineError(
            "No hay archivos nuevos en 01_Videos. Copia ahi los videos o audios y vuelve a pulsar el trigger."
        )

    day = run_date or date.today()
    day_label = day.isoformat()
    generated_at = datetime.now()
    total_files = len(media_files)
    emit_progress(progress, "pipeline_started", total_files=total_files, day_label=day_label)
    transcript_folder = paths.individual_transcripts / day_label
    archive_folder = paths.processed_videos / day_label
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
        log(f"Transcribiendo: {media_file.name}")
        transcript_name = f"{media_file.stem}.txt"
        transcript_path = unique_file_path(transcript_folder, transcript_name)
        transcript_text = clean_transcript_text(active_transcriber.transcribe(media_file))
        transcript_path.write_text(transcript_text + "\n", encoding="utf-8")

        archive_path = unique_file_path(archive_folder, media_file.name)
        shutil.move(str(media_file), archive_path)
        processed += 1
        log(f"Guardado: {transcript_path.name}")
        emit_progress(
            progress,
            "file_finished",
            current_file=index,
            total_files=total_files,
            file_name=media_file.name,
            transcript_name=transcript_path.name,
        )

    export_file = rebuild_export_for_day(paths, day_label, generated_at=generated_at, log=log)
    log("Proceso terminado correctamente.")
    emit_progress(
        progress,
        "pipeline_finished",
        processed_files=processed,
        total_files=total_files,
        export_file=export_file,
    )
    return RunSummary(
        processed_files=processed,
        transcript_folder=transcript_folder,
        archive_folder=archive_folder,
        export_file=export_file,
    )
