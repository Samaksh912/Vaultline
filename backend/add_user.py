import argparse
import os
import pickle
import shutil
import time
import wave

import cv2
import numpy as np
import pyaudio
from scipy.io.wavfile import read

from main_functions import GMM, extract_features, img_to_encoding

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FACE_DATABASE_PATH = os.path.join(BASE_DIR, 'face_database', 'embeddings.pickle')
GMM_DIR = os.path.join(BASE_DIR, 'gmm_models')
VOICE_DATABASE_DIR = os.path.join(BASE_DIR, 'voice_database')


def _load_face_database():
    if os.path.exists(FACE_DATABASE_PATH):
        with open(FACE_DATABASE_PATH, 'rb') as database:
            return pickle.load(database)
    return {}


def _save_face_database(db):
    os.makedirs(os.path.dirname(FACE_DATABASE_PATH), exist_ok=True)
    with open(FACE_DATABASE_PATH, 'wb') as database:
        pickle.dump(db, database, protocol=pickle.HIGHEST_PROTOCOL)


def _face_image_to_embedding(face_image_path):
    image = cv2.imread(face_image_path)
    if image is None:
        raise ValueError(f'Unable to read face image: {face_image_path}')

    face_cascade = cv2.CascadeClassifier('./haarcascades/haarcascade_frontalface_default.xml')
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    faces = face_cascade.detectMultiScale(gray, 1.3, 5)

    if len(faces) != 1:
        raise ValueError('Exactly one face is required in the uploaded image.')

    x, y, w, h = faces[0]
    roi = image[max(0, y - 10):min(image.shape[0], y + h + 10), max(0, x - 10):min(image.shape[1], x + w + 10)]
    img = cv2.resize(roi, (96, 96))
    return img_to_encoding(img)


def _prepare_voice_samples(name, voice_files):
    voice_samples = list(voice_files or [])
    if not voice_samples:
        raise ValueError('At least one voice sample is required.')

    while len(voice_samples) < 3:
        voice_samples.extend(voice_samples[: max(1, 3 - len(voice_samples))])

    voice_dir = os.path.join(VOICE_DATABASE_DIR, name)
    os.makedirs(voice_dir, exist_ok=True)
    for idx, source in enumerate(voice_samples[:3], 1):
        target = os.path.join(voice_dir, f'{idx}.wav')
        shutil.copy2(source, target)

    return voice_dir


def add_user_from_files(name, face_image_path, voice_files):
    if not name or name == 'unknown':
        raise ValueError('A valid user name is required.')

    db = _load_face_database()
    if name in db:
        raise ValueError('Name Already Exists! Try Another Name...')

    embedding = _face_image_to_embedding(face_image_path)
    db[name] = embedding
    _save_face_database(db)

    voice_dir = _prepare_voice_samples(name, voice_files)
    features = np.array([])
    count = 0
    for voice_path in sorted(os.listdir(voice_dir)):
        path = os.path.join(voice_dir, voice_path)
        (sr, audio) = read(path)
        vector = extract_features(audio, sr)
        if features.size == 0:
            features = vector
        else:
            features = np.vstack((features, vector))
        count += 1

        if count == 3:
            gmm = GMM(n_components=16, max_iter=200, covariance_type='diag', n_init=3)
            gmm.fit(features)
            os.makedirs(GMM_DIR, exist_ok=True)
            with open(os.path.join(GMM_DIR, f'{name}.gmm'), 'wb') as model_file:
                pickle.dump(gmm, model_file)
            features = np.asarray(())
            count = 0

    return True


def add_user():
    name = input('Enter Name:')
    db = _load_face_database()
    if name in db or name == 'unknown':
        print('Name Already Exists! Try Another Name...')
        return

    cap = cv2.VideoCapture(0)
    cap.set(3, 640)
    cap.set(4, 480)

    face_cascade = cv2.CascadeClassifier('./haarcascades/haarcascade_frontalface_default.xml')
    i = 3
    face_found = False
    while True:
        _, frame = cap.read()
        frame = cv2.flip(frame, 1, 0)
        cv2.putText(frame, 'Keep Your Face infront of Camera', (100, 200), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
        cv2.putText(frame, 'Starting', (260, 270), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
        cv2.putText(frame, str(i), (290, 330), cv2.FONT_HERSHEY_SIMPLEX, 1.3, (255, 255, 255), 3)
        i -= 1
        cv2.imshow('frame', frame)
        cv2.waitKey(1000)
        if i < 0:
            break

    start_time = time.time()
    while True:
        curr_time = time.time()
        _, frame = cap.read()
        frame = cv2.flip(frame, 1, 0)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        faces = face_cascade.detectMultiScale(gray, 1.3, 5)

        if len(faces) == 1:
            for (x, y, w, h) in faces:
                roi = frame[y - 10:y + h + 10, x - 10:x + w + 10]
                fh, fw = roi.shape[:2]
                if fh < 20 and fw < 20:
                    continue
                face_found = True
                cv2.rectangle(frame, (x - 10, y - 10), (x + w + 10, y + h + 10), (255, 200, 200), 2)
        if curr_time - start_time >= 3:
            break
        cv2.imshow('frame', frame)
        cv2.waitKey(1)

    cap.release()
    cv2.destroyAllWindows()

    if face_found:
        try:
            roi = frame[0:0, 0:0]
            for (x, y, w, h) in faces:
                roi = frame[y - 10:y + h + 10, x - 10:x + w + 10]
            if roi.size == 0:
                raise ValueError('No face was extracted from the frame.')
            img = cv2.resize(roi, (96, 96))
            db[name] = img_to_encoding(img)
            _save_face_database(db)
        except Exception as exc:
            print(f'Face enrollment failed: {exc}')
            return
    elif len(faces) > 1:
        print('More than one faces found. Try again...')
        return
    else:
        print('There was no face found in the frame. Try again...')
        return

    os.system('cls' if os.name == 'nt' else 'clear')

    FORMAT = pyaudio.paInt16
    CHANNELS = 2
    RATE = 44100
    CHUNK = 1024
    RECORD_SECONDS = 3
    source = os.path.join(VOICE_DATABASE_DIR, name)
    os.makedirs(source, exist_ok=True)

    for i in range(3):
        audio = pyaudio.PyAudio()
        if i == 0:
            j = 3
            while j >= 0:
                time.sleep(1.0)
                os.system('cls' if os.name == 'nt' else 'clear')
                print('Speak your name in {} seconds'.format(j))
                j -= 1
        elif i == 1:
            time.sleep(2.0)
            print('Speak your name one more time')
            time.sleep(0.8)
        else:
            time.sleep(2.0)
            print('Speak your name one last time')
            time.sleep(0.8)

        stream = audio.open(format=FORMAT, channels=CHANNELS, rate=RATE, input=True, frames_per_buffer=CHUNK)
        print('recording...')
        frames = []
        for _ in range(0, int(RATE / CHUNK * RECORD_SECONDS)):
            data = stream.read(CHUNK)
            frames.append(data)
        stream.stop_stream()
        stream.close()
        audio.terminate()

        wave_file = wave.open(source + '/' + str((i + 1)) + '.wav', 'wb')
        wave_file.setnchannels(CHANNELS)
        wave_file.setsampwidth(audio.get_sample_size(FORMAT))
        wave_file.setframerate(RATE)
        wave_file.writeframes(b''.join(frames))
        wave_file.close()
        print('Done')

    features = np.array([])
    count = 0
    for path in sorted(os.listdir(source)):
        path = os.path.join(source, path)
        (sr, audio) = read(path)
        vector = extract_features(audio, sr)
        if features.size == 0:
            features = vector
        else:
            features = np.vstack((features, vector))
        count += 1
        if count == 3:
            gmm = GMM(n_components=16, max_iter=200, covariance_type='diag', n_init=3)
            gmm.fit(features)
            os.makedirs(GMM_DIR, exist_ok=True)
            with open(os.path.join(GMM_DIR, f'{name}.gmm'), 'wb') as model_file:
                pickle.dump(gmm, model_file)
            print(name + ' added successfully')
            features = np.asarray(())
            count = 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', default=None)
    parser.add_argument('--face', default=None)
    parser.add_argument('--voice', default=None)
    args = parser.parse_args()

    if args.name and args.face and args.voice:
        add_user_from_files(args.name, args.face, [args.voice])
    else:
        add_user()
