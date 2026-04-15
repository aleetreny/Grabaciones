from __future__ import annotations

import os
import queue
import subprocess
import sys
import threading
import traceback
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

from pipeline import PipelineError, open_in_file_browser, project_paths, run_pipeline

TITLE = "Transcribir audios"

try:
    import tkinter as tk
    from tkinter import Tk, messagebox, ttk

    TK_AVAILABLE = True
except Exception:  # noqa: BLE001
    tk = None  # type: ignore[assignment]
    Tk = None  # type: ignore[assignment]
    messagebox = None  # type: ignore[assignment]
    ttk = None  # type: ignore[assignment]
    TK_AVAILABLE = False


def repository_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parents[3]
    return Path(__file__).resolve().parents[1]


def log_file_path() -> Path:
    log_folder = repository_root() / "_interno" / "logs"
    log_folder.mkdir(parents=True, exist_ok=True)
    return log_folder / "ultima_ejecucion.txt"


def diagnostic_file_path() -> Path:
    return repository_root() / "DIAGNOSTICO - ultimo error.txt"


def execution_lock_path() -> Path:
    lock_folder = repository_root() / "_interno" / "logs"
    lock_folder.mkdir(parents=True, exist_ok=True)
    return lock_folder / "flujo_en_curso.lock"


def write_log(message: str) -> None:
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with log_file_path().open("a", encoding="utf-8") as handle:
        handle.write(f"[{timestamp}] {message}\n")


def reset_log() -> None:
    log_file_path().write_text("", encoding="utf-8")


def clear_diagnostic_file() -> None:
    report = diagnostic_file_path()
    if report.exists():
        report.unlink()


def escape_applescript(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def silent_mode() -> bool:
    return (
        os.environ.get("TRANSCRIPCION_SILENCIOSA") == "1"
        or os.environ.get("PROCESAR_LLAMADAS_SILENCIOSO") == "1"
    )


def show_info(message: str) -> None:
    if silent_mode():
        print(message)
        return

    if sys.platform == "darwin":
        safe_message = escape_applescript(message)
        safe_title = escape_applescript(TITLE)
        subprocess.run(
            [
                "osascript",
                "-e",
                f'display dialog "{safe_message}" with title "{safe_title}" buttons {{"OK"}} default button "OK"',
            ],
            check=False,
        )
        return

    print(message)


def show_error(message: str) -> None:
    if silent_mode():
        print(message, file=sys.stderr)
        return

    if sys.platform == "darwin":
        safe_message = escape_applescript(message)
        safe_title = escape_applescript(TITLE)
        subprocess.run(
            [
                "osascript",
                "-e",
                f'display alert "{safe_title}" message "{safe_message}" as critical',
            ],
            check=False,
        )
        return

    print(message, file=sys.stderr)


def summarize_unexpected_error(error: BaseException) -> str:
    message = str(error).strip()
    lowered = message.lower()

    if any(token in lowered for token in ("ssl", "certificate", "urlopen", "download", "http error", "connection")):
        return (
            "No se ha podido descargar o cargar el modelo de Whisper. "
            "Comprueba internet o si la red bloquea la descarga."
        )

    if "torch" in lowered:
        return (
            "Whisper no se ha podido cargar correctamente en este Mac. "
            "Puede faltar alguna dependencia del entorno interno."
        )

    if "permission" in lowered or "denied" in lowered:
        return "macOS ha bloqueado algun archivo del proceso. Comprueba permisos y vuelve a intentarlo."

    if message:
        return f"Detalle tecnico: {error.__class__.__name__}: {message}"
    return f"Detalle tecnico: {error.__class__.__name__}"


def write_diagnostic_report(summary: str, details: str) -> Path:
    report_path = diagnostic_file_path()
    log_path = log_file_path()
    log_contents = ""
    if log_path.exists():
        log_contents = log_path.read_text(encoding="utf-8")

    report_text = "\n".join(
        [
            "DIAGNOSTICO DEL ULTIMO ERROR",
            "",
            f"Fecha: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            f"Host: {os.environ.get('HOSTNAME', '')}",
            f"Usuario: {os.environ.get('USER', '')}",
            f"Python: {sys.version}",
            "",
            "RESUMEN",
            summary,
            "",
            "LOG DE LA EJECUCION",
            log_contents.strip() or "(Sin contenido)",
            "",
            "DETALLE TECNICO",
            details.strip() or "(Sin traceback)",
            "",
        ]
    )
    report_path.write_text(report_text, encoding="utf-8")
    return report_path


def open_path(target: Path) -> None:
    target_text = str(target)
    if sys.platform == "darwin":
        subprocess.Popen(["open", target_text])
        return
    subprocess.Popen(["xdg-open", target_text])


class TerminalProgress:
    def __init__(self) -> None:
        self.total_files = 0
        self.current_file = 0
        self.file_name = ""
        self._last_print_key: tuple[int, int] | None = None

    def _short_name(self, name: str, max_len: int = 36) -> str:
        clean = name.strip() or "(archivo)"
        if len(clean) <= max_len:
            return clean
        return clean[: max_len - 3] + "..."

    def _bar(self, percent: int, width: int = 24) -> str:
        safe_percent = max(0, min(100, percent))
        done = round(width * safe_percent / 100)
        return "#" * done + "-" * (width - done)

    def _print_progress(self, percent: int) -> None:
        if self.total_files <= 0:
            return

        key = (self.current_file, percent)
        if self._last_print_key == key:
            return
        self._last_print_key = key

        file_label = self._short_name(self.file_name)
        bar = self._bar(percent)
        print(
            f"[Progreso {self.current_file}/{self.total_files}] [{bar}] {percent:>3}%  {file_label}",
            flush=True,
        )

    def handle(self, event: str, payload: dict[str, object]) -> None:
        if event == "pipeline_started":
            self.total_files = int(payload.get("total_files", 0))
            self.current_file = 0
            self.file_name = ""
            self._last_print_key = None
            if self.total_files > 0:
                print(f"Inicio de transcripcion: {self.total_files} archivo(s).", flush=True)
            return

        if event == "model_loading":
            model_name = str(payload.get("model_name", "turbo"))
            device = str(payload.get("device", "cpu"))
            print(f"Cargando modelo Whisper ({model_name}, {device})...", flush=True)
            return

        if event == "file_started":
            self.current_file = int(payload.get("current_file", 0))
            self.file_name = str(payload.get("file_name", ""))
            self._last_print_key = None
            self._print_progress(0)
            return

        if event == "file_progress":
            self.current_file = int(payload.get("current_file", self.current_file))
            self.file_name = str(payload.get("file_name", self.file_name))
            percent = int(payload.get("percent", 0))
            # Evita ruido excesivo en terminal manteniendo actualizaciones cada 5%.
            bucketed = percent if percent in (0, 100) else (percent // 5) * 5
            self._print_progress(bucketed)
            return

        if event == "file_finished":
            self.current_file = int(payload.get("current_file", self.current_file))
            self.file_name = str(payload.get("file_name", self.file_name))
            self._print_progress(100)
            return

        if event == "pipeline_finished":
            processed = int(payload.get("processed_files", 0))
            print(f"Lote completado. Archivos procesados: {processed}.", flush=True)
            return


@contextmanager
def single_execution_lock():
    lock_file = execution_lock_path().open("a+b")
    acquired = False
    try:
        lock_file.seek(0)
        lock_file.write(b" ")
        lock_file.flush()
        lock_file.seek(0)

        if os.name == "nt":
            import msvcrt

            msvcrt.locking(lock_file.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl

            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

        lock_file.seek(0)
        lock_file.truncate()
        lock_file.write(str(os.getpid()).encode("ascii", errors="ignore"))
        lock_file.flush()
        acquired = True
        yield True
    except OSError:
        yield False
    finally:
        if acquired:
            try:
                if os.name == "nt":
                    import msvcrt

                    lock_file.seek(0)
                    msvcrt.locking(lock_file.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    import fcntl

                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
        lock_file.close()


def run_headless() -> int:
    reset_log()
    clear_diagnostic_file()
    paths = project_paths(repository_root())
    paths.ensure_directories()
    write_log("Inicio de ejecucion.")
    terminal_progress = TerminalProgress()

    def headless_log(message: str) -> None:
        write_log(message)
        print(message, flush=True)

    try:
        summary = run_pipeline(
            paths,
            log=headless_log,
            progress=terminal_progress.handle,
        )
    except PipelineError as error:
        write_log(f"Proceso detenido: {error}")
        report = write_diagnostic_report(str(error), "")
        if not silent_mode():
            try:
                open_path(report)
            except Exception:  # noqa: BLE001
                pass
        show_error(f"{error}\n\nSe ha guardado un diagnostico en:\n{report}")
        return 1
    except Exception:  # noqa: BLE001
        details = traceback.format_exc()
        write_log(details)
        summary_message = summarize_unexpected_error(sys.exc_info()[1] or RuntimeError("Error desconocido"))
        report = write_diagnostic_report(summary_message, details)
        if not silent_mode():
            try:
                open_path(report)
            except Exception:  # noqa: BLE001
                pass
        show_error(f"{summary_message}\n\nSe ha guardado un diagnostico en:\n{report}")
        return 1

    if not silent_mode():
        open_in_file_browser(summary.transcript_folder)
    write_log(f"Transcripciones guardadas en: {summary.transcript_folder}")
    show_info(
        "Proceso completado.\n\n"
        f"Audios procesados: {summary.processed_files}\n"
        f"Carpeta de transcripciones: {summary.transcript_folder.name}"
    )
    return 0


class ProcessMonitorApp:
    def __init__(self) -> None:
        self.root = Tk()
        self.root.title(TITLE)
        self.root.geometry("580x360")
        self.root.minsize(540, 320)

        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.worker: threading.Thread | None = None
        self.running = False
        self.paths = project_paths(repository_root())
        self.paths.ensure_directories()
        self.transcript_folder: Path | None = None
        self.diagnostic_file: Path | None = None

        self.status_var = tk.StringVar(value="Preparando proceso...")
        self.detail_var = tk.StringVar(value="Puedes minimizar esta ventana y seguir trabajando.")
        self.counter_var = tk.StringVar(value="Pendiente de iniciar")
        self.percent_var = tk.StringVar(value="0%")

        self._build_ui()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(80, self.present_window)
        self.root.after(150, self.poll_events)
        self.start()

    def _build_ui(self) -> None:
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        outer = ttk.Frame(self.root, padding=16)
        outer.grid(sticky="nsew")
        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(4, weight=1)

        title = ttk.Label(outer, text=TITLE, font=("", 15, "bold"))
        title.grid(row=0, column=0, sticky="w")

        subtitle = ttk.Label(
            outer,
            text="El progreso se actualiza en tiempo real y cada transcripcion se guarda al terminar cada audio.",
            wraplength=520,
            justify="left",
        )
        subtitle.grid(row=1, column=0, sticky="w", pady=(4, 14))

        status = ttk.Label(
            outer,
            textvariable=self.status_var,
            font=("", 11, "bold"),
            wraplength=520,
            justify="left",
        )
        status.grid(row=2, column=0, sticky="w")

        detail = ttk.Label(
            outer,
            textvariable=self.detail_var,
            wraplength=520,
            justify="left",
        )
        detail.grid(row=3, column=0, sticky="w", pady=(6, 10))

        progress_frame = ttk.Frame(outer)
        progress_frame.grid(row=4, column=0, sticky="nsew")
        progress_frame.columnconfigure(0, weight=1)
        progress_frame.rowconfigure(2, weight=1)

        progress_header = ttk.Frame(progress_frame)
        progress_header.grid(row=0, column=0, sticky="ew")
        progress_header.columnconfigure(0, weight=1)
        progress_header.columnconfigure(1, weight=0)

        counter = ttk.Label(progress_header, textvariable=self.counter_var)
        counter.grid(row=0, column=0, sticky="w")

        percent = ttk.Label(progress_header, textvariable=self.percent_var, font=("", 11, "bold"))
        percent.grid(row=0, column=1, sticky="e")

        self.file_progress = ttk.Progressbar(progress_frame, mode="determinate", maximum=100)
        self.file_progress.grid(row=1, column=0, sticky="ew", pady=(6, 10))

        self.log_box = tk.Text(
            progress_frame,
            height=9,
            state="disabled",
            wrap="word",
            font="TkFixedFont",
            bg="#f7f7f7",
        )
        self.log_box.grid(row=2, column=0, sticky="nsew", pady=(12, 0))

        buttons = ttk.Frame(outer)
        buttons.grid(row=5, column=0, sticky="ew", pady=(14, 0))
        buttons.columnconfigure(0, weight=1)
        buttons.columnconfigure(1, weight=1)
        buttons.columnconfigure(2, weight=1)

        self.background_button = ttk.Button(
            buttons,
            text="Dejar en segundo plano",
            command=self.root.iconify,
        )
        self.background_button.grid(row=0, column=0, sticky="ew", padx=(0, 8))

        self.open_button = ttk.Button(
            buttons,
            text="Abrir resultado",
            command=self.open_result,
            state="disabled",
        )
        self.open_button.grid(row=0, column=1, sticky="ew", padx=8)

        self.close_button = ttk.Button(buttons, text="Cerrar", command=self.on_close)
        self.close_button.grid(row=0, column=2, sticky="ew", padx=(8, 0))

    def append_log(self, message: str) -> None:
        self.log_box.configure(state="normal")
        self.log_box.insert("end", f"{message}\n")
        self.log_box.see("end")
        self.log_box.configure(state="disabled")

    def present_window(self) -> None:
        try:
            self.root.update_idletasks()

            width = max(self.root.winfo_width(), 580)
            height = max(self.root.winfo_height(), 360)
            screen_width = self.root.winfo_screenwidth()
            screen_height = self.root.winfo_screenheight()
            x = max((screen_width - width) // 2, 0)
            y = max((screen_height - height) // 3, 0)

            self.root.geometry(f"{width}x{height}+{x}+{y}")
            self.root.deiconify()
            self.root.lift()
            self.root.focus_force()
            self.root.attributes("-topmost", True)
            self.root.after(1200, lambda: self.root.attributes("-topmost", False))
        except Exception:  # noqa: BLE001
            return

    def start(self) -> None:
        reset_log()
        clear_diagnostic_file()
        write_log("Inicio de ejecucion.")
        self.running = True
        self.append_log("Inicio de ejecucion.")
        self.worker = threading.Thread(target=self.worker_main, daemon=True)
        self.worker.start()

    def worker_main(self) -> None:
        try:
            summary = run_pipeline(
                self.paths,
                log=self.log_from_worker,
                progress=self.progress_from_worker,
            )
        except PipelineError as error:
            self.events.put(("pipeline_error", error))
        except Exception as error:  # noqa: BLE001
            details = traceback.format_exc()
            write_log(details)
            self.events.put(("unexpected_error", {"error": error, "details": details}))
        else:
            self.events.put(("done", summary))

    def log_from_worker(self, message: str) -> None:
        write_log(message)
        self.events.put(("log", message))

    def progress_from_worker(self, event: str, payload: dict[str, object]) -> None:
        self.events.put(("progress", (event, payload)))

    def poll_events(self) -> None:
        while True:
            try:
                event_type, payload = self.events.get_nowait()
            except queue.Empty:
                break

            if event_type == "log":
                self.append_log(str(payload))
            elif event_type == "progress":
                progress_event, progress_payload = payload  # type: ignore[misc]
                self.handle_progress(progress_event, progress_payload)
            elif event_type == "pipeline_error":
                self.handle_pipeline_error(payload)  # type: ignore[arg-type]
            elif event_type == "unexpected_error":
                self.handle_unexpected_error(payload)  # type: ignore[arg-type]
            elif event_type == "done":
                self.handle_done(payload)

        self.root.after(150, self.poll_events)

    def handle_progress(self, event: str, payload: dict[str, object]) -> None:
        if event == "pipeline_started":
            total_files = int(payload["total_files"])
            self.file_progress.configure(maximum=100, value=0)
            self.status_var.set("Proceso iniciado")
            self.counter_var.set(f"Archivos detectados: {total_files}")
            self.percent_var.set("0%")
            return

        if event == "model_loading":
            model_name = str(payload.get("model_name", "large-v3"))
            device = str(payload.get("device", "cpu"))
            self.status_var.set("Cargando Whisper")
            self.detail_var.set(f"Modelo {model_name} en {device}. El primer arranque puede tardar.")
            self.percent_var.set("0%")
            return

        if event == "model_ready":
            self.status_var.set("Whisper listo")
            self.detail_var.set("Empieza la transcripcion.")
            return

        if event == "file_started":
            current_file = int(payload["current_file"])
            total_files = int(payload["total_files"])
            file_name = str(payload["file_name"])
            self.status_var.set("Transcribiendo")
            self.detail_var.set(file_name)
            self.counter_var.set(f"Archivo {current_file} de {total_files}")
            self.file_progress.configure(maximum=100, value=0)
            self.percent_var.set("0%")
            return

        if event == "file_progress":
            percent = int(payload["percent"])
            current_file = int(payload["current_file"])
            total_files = int(payload["total_files"])
            file_name = str(payload["file_name"])
            self.status_var.set("Transcribiendo")
            self.detail_var.set(file_name)
            self.counter_var.set(f"Archivo {current_file} de {total_files}")
            self.file_progress.configure(maximum=100, value=percent)
            self.percent_var.set(f"{percent}%")
            return

        if event == "file_finished":
            current_file = int(payload["current_file"])
            total_files = int(payload["total_files"])
            transcript_name = str(payload["transcript_name"])
            self.status_var.set("Archivo completado")
            self.detail_var.set(f"Guardado: {transcript_name}")
            self.counter_var.set(f"Archivo {current_file} de {total_files}")
            self.file_progress.configure(maximum=100, value=100)
            self.percent_var.set("100%")
            return

        if event == "pipeline_finished":
            processed_files = int(payload["processed_files"])
            transcript_folder = payload.get("transcript_folder")
            if isinstance(transcript_folder, Path):
                self.transcript_folder = transcript_folder
            self.status_var.set("Proceso completado")
            self.detail_var.set("Ya puedes abrir las transcripciones.")
            self.counter_var.set(f"Audios procesados: {processed_files}")
            self.file_progress.configure(maximum=100, value=100)
            self.percent_var.set("100%")

    def handle_pipeline_error(self, error: PipelineError) -> None:
        self.running = False
        self.present_window()
        self.diagnostic_file = write_diagnostic_report(str(error), "")
        self.status_var.set("Proceso detenido")
        self.detail_var.set(str(error))
        self.counter_var.set("No se ha completado el lote")
        self.append_log(f"Proceso detenido: {error}")
        self.open_button.configure(state="normal", text="Abrir diagnostico")
        try:
            open_path(self.diagnostic_file)
        except Exception:  # noqa: BLE001
            pass
        messagebox.showerror(
            TITLE,
            f"{error}\n\n"
            f"Se ha guardado un diagnostico en:\n{self.diagnostic_file}",
        )

    def handle_unexpected_error(self, payload: dict[str, object]) -> None:
        self.running = False
        self.present_window()
        error = payload.get("error")
        details = str(payload.get("details", ""))
        summary = summarize_unexpected_error(error) if isinstance(error, BaseException) else "Ha ocurrido un error inesperado."
        self.diagnostic_file = write_diagnostic_report(summary, details)
        self.status_var.set("Error inesperado")
        self.detail_var.set(summary)
        self.counter_var.set("Proceso interrumpido")
        self.append_log(summary)
        self.open_button.configure(state="normal", text="Abrir diagnostico")
        try:
            open_path(self.diagnostic_file)
        except Exception:  # noqa: BLE001
            pass
        messagebox.showerror(
            TITLE,
            f"{summary}\n\n"
            f"Se ha guardado un diagnostico en:\n{self.diagnostic_file}",
        )

    def handle_done(self, summary: object) -> None:
        self.running = False
        self.present_window()
        self.open_button.configure(state="normal", text="Abrir transcripciones")

        transcript_folder = getattr(summary, "transcript_folder", None)
        if isinstance(transcript_folder, Path):
            self.transcript_folder = transcript_folder
            open_in_file_browser(transcript_folder)

        processed_files = int(getattr(summary, "processed_files", 0))
        messagebox.showinfo(
            TITLE,
            "Proceso completado.\n\n"
            f"Audios procesados: {processed_files}\n"
            f"Carpeta: {self.transcript_folder.name if self.transcript_folder else ''}",
        )

    def open_result(self) -> None:
        if self.diagnostic_file is not None and self.diagnostic_file.exists():
            open_path(self.diagnostic_file)
            return
        if self.transcript_folder is not None:
            open_in_file_browser(self.transcript_folder)

    def on_close(self) -> None:
        if self.running:
            self.root.iconify()
            return
        self.root.destroy()

    def run(self) -> int:
        self.root.mainloop()
        return 0


def main() -> int:
    with single_execution_lock() as acquired:
        if not acquired:
            show_info(
                "Ya hay un proceso en marcha en esta carpeta. "
                "Espera a que termine o abre la ventana que ya esta en segundo plano."
            )
            return 0

        if silent_mode() or not TK_AVAILABLE:
            return run_headless()
        app = ProcessMonitorApp()
        return app.run()


if __name__ == "__main__":
    raise SystemExit(main())
