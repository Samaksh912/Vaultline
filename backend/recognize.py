import argparse
import os
import pickle
import time
import wave

import cv2
import numpy as np
import pyaudio
from scipy.io.wavfile import read

from main_functions import extract_features, img_to_encoding

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
GMM_DIR = os.path.join(BASE_DIR, 'gmm_models')
FACE_DATABASE_PATH = os.path.join(BASE_DIR, 'face_database', 'embeddings.pickle')
CASCADE_PATH = os.path.join(BASE_DIR, 'haarcascades', 'haarcascade_frontalface_default.xml')


def _candidate_model_paths(expected_user=None):
    if not os.path.isdir(GMM_DIR):
        return []

    if expected_user:
        expected_path = os.path.join(GMM_DIR, f'{expected_user}.gmm')
        if os.path.exists(expected_path):
            return [expected_path]

    return sorted(
        os.path.join(GMM_DIR, fname)
        for fname in os.listdir(GMM_DIR)
        if fname.lower().endswith('.gmm')
    )


def _score_voice_identity(voice_wav_path, expected_user=None):
    model_paths = _candidate_model_paths(expected_user)
    if not model_paths:
        return None, float('-inf'), float('-inf')

    sr, audio = read(voice_wav_path)
    vector = extract_features(audio, sr)

    best_name = None
    best_score = float('-inf')
    second_score = float('-inf')

    for model_path in model_paths:
        with open(model_path, 'rb') as handle:
            gmm = pickle.load(handle)
        scores = np.asarray(gmm.score(vector), dtype=float)
        score = float(scores.sum())
        speaker_name = os.path.basename(model_path).rsplit('.gmm', 1)[0]

        if score > best_score:
            second_score = best_score
            best_score = score
            best_name = speaker_name
        elif score > second_score:
            second_score = score

    return best_name, best_score, second_score


def _voice_identity(voice_wav_path, expected_user=None):
    identity, score, _ = _score_voice_identity(voice_wav_path, expected_user=expected_user)
    return identity, score


def _face_identity(face_image_path):
    with open(FACE_DATABASE_PATH, 'rb') as db_handle:
        database = pickle.load(db_handle)
    image = cv2.imread(face_image_path)
    if image is None:
        raise ValueError(f'Unable to read face image: {face_image_path}')

    cascade = cv2.CascadeClassifier(CASCADE_PATH)
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    faces = cascade.detectMultiScale(gray, 1.3, 5)
    if len(faces) != 1:
        raise ValueError('Exactly one face is required in the uploaded image.')

    x, y, w, h = faces[0]
    roi = image[max(0, y - 10):min(image.shape[0], y + h + 10), max(0, x - 10):min(image.shape[1], x + w + 10)]
    img = cv2.resize(roi, (96, 96))
    encoding = img_to_encoding(img)

    min_dist = 100
    name = 'unknown'
    for known_name in database:
        dist = np.linalg.norm(np.subtract(database[known_name], encoding))
        if dist < min_dist:
            min_dist = dist
            name = known_name
    return name, min_dist


def recognize_from_files(face_image_path, voice_wav_path, expected_user=None):
    identity, score, second_score = _score_voice_identity(voice_wav_path, expected_user=expected_user)
    if identity is None or identity == 'unknown':
        return False

    if expected_user and identity != expected_user:
        return False

    if expected_user and second_score != float('-inf'):
        score_gap = score - second_score
        if score_gap < 1.5:
            return False

    name, min_dist = _face_identity(face_image_path)
    if min_dist <= 0.4 and name == identity:
        return True
    return False


def recognize():
    FORMAT = pyaudio.paInt16
    CHANNELS = 2
    RATE = 44100
    CHUNK = 1024
    RECORD_SECONDS = 4
    FILENAME = './test.wav'

    audio = pyaudio.PyAudio()
    stream = audio.open(format=FORMAT, channels=CHANNELS, rate=RATE, input=True, frames_per_buffer=CHUNK)
    time.sleep(2.0)
    print('recording...')
    frames = []
    for _ in range(0, int(RATE / CHUNK * RECORD_SECONDS)):
        data = stream.read(CHUNK)
        frames.append(data)
    print('finished recording')

    stream.stop_stream()
    stream.close()
    audio.terminate()

    wave_file = wave.open(FILENAME, 'wb')
    wave_file.setnchannels(CHANNELS)
    wave_file.setsampwidth(audio.get_sample_size(FORMAT))
    wave_file.setframerate(RATE)
    wave_file.writeframes(b''.join(frames))
    wave_file.close()

    print('Recognized as - ', _voice_identity(FILENAME)[0])
    print('Keep Your face infront of the camera')
    cap = cv2.VideoCapture(0)
    cap.set(3, 640)
    cap.set(4, 480)
    cascade = cv2.CascadeClassifier('./haarcascades/haarcascade_frontalface_default.xml')

    time.sleep(1.0)
    start_time = time.time()
    while True:
        curr_time = time.time()
        _, frame = cap.read()
        frame = cv2.flip(frame, 1, 0)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        faces = cascade.detectMultiScale(gray, 1.3, 5)

        if len(faces) == 1:
            for (x, y, w, h) in faces:
                roi = frame[y - 10:y + h + 10, x - 10:x + w + 10]
                fh, fw = roi.shape[:2]
                if fh < 20 or fw < 20:
                    continue
                img = cv2.resize(roi, (96, 96))
                encoding = img_to_encoding(img)
                with open(FACE_DATABASE_PATH, 'rb') as db_handle:
                    database = pickle.load(db_handle)
                min_dist = 100
                name = 'unknown'
                for known_name in database:
                    dist = np.linalg.norm(np.subtract(database[known_name], encoding))
                    if dist < min_dist:
                        min_dist = dist
                        name = known_name
                if min_dist <= 0.4 and name == _voice_identity(FILENAME)[0]:
                    print('Door Unlocked! Welcome ' + str(name))
                    cap.release()
                    cv2.destroyAllWindows()
                    return

        if curr_time - start_time >= 3:
            break
        cv2.waitKey(1)
        cv2.imshow('frame', frame)

    cap.release()
    cv2.destroyAllWindows()
    print('Not Recognized! Try again...')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--face', default=None)
    parser.add_argument('--voice', default=None)
    parser.add_argument('--user-id', default=None)
    args = parser.parse_args()

    if args.face and args.voice:
        print('match' if recognize_from_files(args.face, args.voice, args.user_id) else 'no-match')
    else:
        recognize()
