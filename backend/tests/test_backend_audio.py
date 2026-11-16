import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import backend_api


class AudioConversionTest(unittest.TestCase):
    def test_ensure_wav_converts_non_wav_audio(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            source = Path(tmp_dir) / 'sample.m4a'
            subprocess.run(
                ['ffmpeg', '-y', '-f', 'lavfi', '-i', 'sine=frequency=1000:duration=0.2', str(source)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

            converted = backend_api._ensure_wav(str(source))

            self.assertTrue(converted.endswith('.wav'))
            self.assertTrue(os.path.exists(converted))


if __name__ == '__main__':
    unittest.main()
