from __future__ import annotations

import ctypes
import os
import queue
import subprocess
import sys
import threading
import traceback
from datetime import datetime
from pathlib import Path

from pipeline import (
    PipelineError,
    ProgressCallback,
    open_in_file_browser,
    project_paths,
    run_pipeline,
)

TITLE = "Procesar llamadas"

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


def write_log(message: str) -> None:
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with log_file_path().open("a", encoding="utf-8") as handle:
        handle.write(f"[{timestamp}] {message}\n")


def reset_log() -> None:
    log_file_path().write_text("", encoding="utf-8")


def escape_applescript(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def silent_mode() -> bool:
    return os.environ.get("PROCESAR_LLAMADAS_SILENCIOSO") == "1"


def show_info(message: str) -> None:
    if silent_mode():
        print(message)
        return

    if sys.platform.startswith("win"):
        ctypes.windll.user32.MessageBoxW(None, message, TITLE, 0x40)
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

    if sys.platform.startswith("win"):
        ctypes.windll.user32.MessageBoxW(None, message, TITLE, 0x10)
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


def run_headless() -> int:
    reset_log()
    paths = project_paths(repository_root())
    paths.ensure_directories()
    write_log("Inicio de ejecucion.")

    try:
        summary = run_pipeline(paths, log=write_log)
    except PipelineError as error:
        write_log(f"Proceso detenido: {error}")
        show_info(str(error))
        return 1
    except Exception:  # noqa: BLE001
        details = traceback.format_exc()
        write_log(details)
        show_error(
            "Ha ocurrido un error inesperado.\n\n"
            f"Revisa el log en:\n{log_file_path()}"
        )
        return 1

    open_in_file_browser(summary.export_file.parent)
    write_log(f"Archivo final generado: {summary.export_file}")
    show_info(
        "Proceso completado.\n\n"
        f"Videos procesados: {summary.processed_files}\n"
        f"Archivo final: {summary.export_file.name}"
    )
    return 0


class ProcessMonitorApp:
    def __init__(self) -> None:
        self.root = Tk()
        self.root.title(TITLE)
        self.root.geometry("560x340")
        self.root.minsize(520, 300)

        self.events: queue.Queue[tuple[str, object]] = queue.Queue()
        self.worker: threading.Thread | None = None
        self.running = False
        self.paths = project_paths(repository_root())
        self.paths.ensure_directories()
        self.export_file: Path | None = None

        self.status_var = tk.StringVar(value="Preparando proceso...")
        self.detail_var = tk.StringVar(
            value="Puedes minimizar esta ventana y seguir trabajando."
        )
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
            text="La ventana puede quedarse minimizada mientras el proceso sigue en segundo plano.",
            wraplength=500,
            justify="left",
        )
        subtitle.grid(row=1, column=0, sticky="w", pady=(4, 14))

        status = ttk.Label(
            outer,
            textvariable=self.status_var,
            font=("", 11, "bold"),
            wraplength=500,
            justify="left",
        )
        status.grid(row=2, column=0, sticky="w")

        detail = ttk.Label(
            outer,
            textvariable=self.detail_var,
            wraplength=500,
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

            width = max(self.root.winfo_width(), 560)
            height = max(self.root.winfo_height(), 340)
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

            if sys.platform.startswith("win"):
                hwnd = self.root.winfo_id()
                ctypes.windll.user32.ShowWindow(hwnd, 5)
                ctypes.windll.user32.SetForegroundWindow(hwnd)
        except Exception:  # noqa: BLE001
            return

    def start(self) -> None:
        reset_log()
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
            self.events.put(("unexpected_error", error))
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
                self.handle_unexpected_error()
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
            self.status_var.set("Cargando Whisper")
            self.detail_var.set("Primer arranque o primer uso del dia. Puede tardar un poco.")
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
            self.detail_var.set(transcript_name)
            self.counter_var.set(f"Archivo {current_file} de {total_files}")
            self.file_progress.configure(maximum=100, value=100)
            self.percent_var.set("100%")
            return

        if event == "pipeline_finished":
            processed_files = int(payload["processed_files"])
            self.export_file = payload["export_file"]  # type: ignore[assignment]
            self.status_var.set("Proceso completado")
            self.detail_var.set("Ya puedes abrir el resultado final.")
            self.counter_var.set(f"Videos procesados: {processed_files}")
            self.file_progress.configure(maximum=100, value=100)
            self.percent_var.set("100%")

    def handle_pipeline_error(self, error: PipelineError) -> None:
        self.running = False
        self.present_window()
        self.status_var.set("Proceso detenido")
        self.detail_var.set(str(error))
        self.counter_var.set("No se ha procesado ningun archivo")
        self.append_log(f"Proceso detenido: {error}")
        messagebox.showinfo(TITLE, str(error))

    def handle_unexpected_error(self) -> None:
        self.running = False
        self.present_window()
        self.status_var.set("Error inesperado")
        self.detail_var.set(f"Revisa el log en {log_file_path()}")
        self.counter_var.set("Proceso interrumpido")
        messagebox.showerror(
            TITLE,
            "Ha ocurrido un error inesperado.\n\n"
            f"Revisa el log en:\n{log_file_path()}",
        )

    def handle_done(self, summary: object) -> None:
        self.running = False
        self.present_window()
        self.open_button.configure(state="normal")

        export_file = getattr(summary, "export_file", None)
        if isinstance(export_file, Path):
            self.export_file = export_file
            open_in_file_browser(export_file.parent)

        processed_files = getattr(summary, "processed_files", 0)
        messagebox.showinfo(
            TITLE,
            "Proceso completado.\n\n"
            f"Videos procesados: {processed_files}\n"
            f"Archivo final: {self.export_file.name if self.export_file else ''}",
        )

    def open_result(self) -> None:
        if self.export_file is not None:
            open_in_file_browser(self.export_file.parent)

    def on_close(self) -> None:
        if self.running:
            self.root.iconify()
            return
        self.root.destroy()

    def run(self) -> int:
        self.root.mainloop()
        return 0


def main() -> int:
    if silent_mode():
        return run_headless()
    if not TK_AVAILABLE:
        return run_headless()
    app = ProcessMonitorApp()
    return app.run()


if __name__ == "__main__":
    raise SystemExit(main())
