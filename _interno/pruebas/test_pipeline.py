from __future__ import annotations

import re
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "_interno"))

from pipeline import project_paths, run_pipeline  # noqa: E402

TEST_DAY = date(2026, 4, 7)


class FakeTranscriber:
    def __init__(self, transcript_by_stem: dict[str, str]) -> None:
        self.transcript_by_stem = transcript_by_stem

    def set_file_context(self, current_file: int, total_files: int, file_name: str) -> None:
        _ = (current_file, total_files, file_name)

    def transcribe(self, media_file: Path) -> str:
        return self.transcript_by_stem[media_file.stem]


class PipelineTests(unittest.TestCase):
    def test_run_pipeline_creates_one_txt_per_audio(self) -> None:
        transcript_by_stem = {
            "audio_a": "Transcripcion del audio A.",
            "audio_b": "Transcripcion del audio B.",
        }

        with tempfile.TemporaryDirectory() as temporary_dir:
            paths = project_paths(Path(temporary_dir))
            paths.ensure_directories()

            (paths.incoming_audios / "audio_a.mp3").write_bytes(b"contenido-a")
            (paths.incoming_audios / "audio_b.m4a").write_bytes(b"contenido-b")

            summary = run_pipeline(
                paths=paths,
                transcriber=FakeTranscriber(transcript_by_stem),
                run_date=TEST_DAY,
                log=lambda _: None,
            )

            transcript_folder = paths.transcriptions / TEST_DAY.isoformat()
            archive_folder = paths.processed_audios / TEST_DAY.isoformat()

            self.assertEqual(summary.processed_files, 2)
            self.assertEqual(summary.transcript_folder, transcript_folder)
            self.assertEqual(summary.archive_folder, archive_folder)
            self.assertFalse(list(paths.incoming_audios.iterdir()))

            generated_names = sorted(path.name for path in transcript_folder.glob("*.txt"))
            self.assertEqual(len(generated_names), 2)
            self.assertTrue(any(re.match(r"^\d{4}-\d{2}-\d{2} - audio_a\.txt$", name) for name in generated_names))
            self.assertTrue(any(re.match(r"^\d{4}-\d{2}-\d{2} - audio_b\.txt$", name) for name in generated_names))

            self.assertEqual(
                sorted(path.name for path in archive_folder.iterdir()),
                ["audio_a.mp3", "audio_b.m4a"],
            )

            audio_a_txt = next(path for path in transcript_folder.glob("*.txt") if path.name.endswith("audio_a.txt"))
            audio_b_txt = next(path for path in transcript_folder.glob("*.txt") if path.name.endswith("audio_b.txt"))
            self.assertIn("Transcripcion del audio A.", audio_a_txt.read_text(encoding="utf-8"))
            self.assertIn("Transcripcion del audio B.", audio_b_txt.read_text(encoding="utf-8"))

    def test_run_pipeline_renames_duplicate_transcript_names(self) -> None:
        transcript_by_stem = {
            "reunion": "Texto de reunion.",
        }

        with tempfile.TemporaryDirectory() as temporary_dir:
            paths = project_paths(Path(temporary_dir))
            paths.ensure_directories()

            (paths.incoming_audios / "reunion.mp3").write_bytes(b"uno")
            (paths.incoming_audios / "reunion.m4a").write_bytes(b"dos")

            run_pipeline(
                paths=paths,
                transcriber=FakeTranscriber(transcript_by_stem),
                run_date=TEST_DAY,
                log=lambda _: None,
            )

            transcript_folder = paths.transcriptions / TEST_DAY.isoformat()
            generated = sorted(path.name for path in transcript_folder.glob("*.txt"))
            self.assertEqual(len(generated), 2)
            self.assertTrue(any(re.match(r"^\d{4}-\d{2}-\d{2} - reunion\.txt$", name) for name in generated))
            self.assertTrue(any(re.match(r"^\d{4}-\d{2}-\d{2} - reunion_2\.txt$", name) for name in generated))


if __name__ == "__main__":
    unittest.main()
