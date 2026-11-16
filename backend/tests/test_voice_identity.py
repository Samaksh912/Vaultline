import importlib.util
import os
import pickle
import sys
import tempfile
import types
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]

cv2 = types.ModuleType('cv2')
cv2.imread = lambda path: np.zeros((10, 10, 3), dtype=np.uint8)
cv2.cvtColor = lambda image, code: image
cv2.CascadeClassifier = lambda *args, **kwargs: types.SimpleNamespace(detectMultiScale=lambda *a, **k: [(0, 0, 5, 5)])
sys.modules['cv2'] = cv2

pyaudio = types.ModuleType('pyaudio')
pyaudio.paInt16 = 0
sys.modules['pyaudio'] = pyaudio

scipy = types.ModuleType('scipy')
io_module = types.ModuleType('scipy.io')
wavfile_module = types.ModuleType('scipy.io.wavfile')
wavfile_module.read = lambda path: (16000, np.random.randn(16000).astype(np.float32))
io_module.wavfile = wavfile_module
scipy.io = io_module
sys.modules['scipy'] = scipy
sys.modules['scipy.io'] = io_module
sys.modules['scipy.io.wavfile'] = wavfile_module

main_functions = types.ModuleType('main_functions')
main_functions.extract_features = lambda audio, rate: np.ones((4, 3), dtype=float)
main_functions.img_to_encoding = lambda img: np.ones(128, dtype=float)
sys.modules['main_functions'] = main_functions

spec = importlib.util.spec_from_file_location('recognize', ROOT / 'recognize.py')
recognize = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(recognize)


class FakeGMM:
    def __init__(self, score_value):
        self.score_value = score_value

    def score(self, features):
        return np.full(len(features), self.score_value, dtype=float)


class VoiceIdentityTest(unittest.TestCase):
    def test_expected_user_voice_match_prefers_the_requested_user_model(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            model_dir = root / 'gmm_models'
            model_dir.mkdir()

            with open(model_dir / 'alice.gmm', 'wb') as f:
                pickle.dump(FakeGMM(5.0), f)
            with open(model_dir / 'bob.gmm', 'wb') as f:
                pickle.dump(FakeGMM(20.0), f)

            audio_path = root / 'sample.wav'

            old_cwd = os.getcwd()
            try:
                os.chdir(root)
                recognize.GMM_DIR = str(model_dir)
                identity, _ = recognize._voice_identity(str(audio_path), expected_user='alice')
                self.assertEqual(identity, 'alice')
            finally:
                os.chdir(old_cwd)


if __name__ == '__main__':
    unittest.main()
