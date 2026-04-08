from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "_interno"))

from pipeline import project_paths, rebuild_export_for_day, run_pipeline  # noqa: E402

TEST_DAY = date(2026, 4, 7)


class FakeTranscriber:
    def __init__(self, transcript_by_stem: dict[str, str]) -> None:
        self.transcript_by_stem = transcript_by_stem

    def transcribe(self, media_file: Path) -> str:
        return self.transcript_by_stem[media_file.stem]


def existing_sample_transcriptions() -> list[Path]:
    sample_folder = ROOT / "02_Transcripciones_por_llamada" / TEST_DAY.isoformat()
    files = sorted(sample_folder.glob("*.txt"))
    if files:
        return files

    raise FileNotFoundError(
        "No se han encontrado transcripciones existentes para ejecutar las pruebas rapidas."
    )


class PipelineTests(unittest.TestCase):
    def test_rebuild_export_from_existing_transcriptions(self) -> None:
        samples = existing_sample_transcriptions()

        with tempfile.TemporaryDirectory() as temporary_dir:
            paths = project_paths(Path(temporary_dir))
            paths.ensure_directories()
            day_folder = paths.individual_transcripts / TEST_DAY.isoformat()
            day_folder.mkdir(parents=True, exist_ok=True)

            for sample in samples:
                shutil.copy2(sample, day_folder / sample.name)

            export_file = rebuild_export_for_day(
                paths=paths,
                day_label=TEST_DAY.isoformat(),
                log=lambda _: None,
            )

            export_text = export_file.read_text(encoding="utf-8")
            self.assertIn("RESUMEN DEL LOTE", export_text)
            self.assertIn("LLAMADA 001", export_text)
            self.assertIn(samples[0].stem, export_text)

    def test_run_pipeline_without_whisper_using_existing_transcriptions(self) -> None:
        samples = existing_sample_transcriptions()
        transcript_by_stem = {
            sample.stem: sample.read_text(encoding="utf-8") for sample in samples
        }

        with tempfile.TemporaryDirectory() as temporary_dir:
            paths = project_paths(Path(temporary_dir))
            paths.ensure_directories()

            for stem in transcript_by_stem:
                media_file = paths.incoming_videos / f"{stem}.mp4"
                media_file.write_bytes(b"archivo-de-prueba")

            summary = run_pipeline(
                paths=paths,
                transcriber=FakeTranscriber(transcript_by_stem),
                run_date=TEST_DAY,
                log=lambda _: None,
            )

            transcript_folder = paths.individual_transcripts / TEST_DAY.isoformat()
            archive_folder = paths.processed_videos / TEST_DAY.isoformat()

            self.assertEqual(summary.processed_files, len(samples))
            self.assertFalse(list(paths.incoming_videos.iterdir()))
            self.assertEqual(len(list(transcript_folder.glob("*.txt"))), len(samples))
            self.assertEqual(len(list(archive_folder.glob("*.mp4"))), len(samples))

            export_text = summary.export_file.read_text(encoding="utf-8")
            self.assertIn("Total de llamadas", export_text)
            self.assertIn("LLAMADA 002", export_text)


if __name__ == "__main__":
    unittest.main()
