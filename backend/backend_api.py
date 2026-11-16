import os
import shutil
import subprocess
from typing import List

from flask import Flask, jsonify, request
from werkzeug.utils import secure_filename

from add_user import add_user_from_files
from recognize import recognize_from_files

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = os.path.join(BASE_DIR, 'mobile_uploads')
os.makedirs(UPLOAD_DIR, exist_ok=True)


def _ensure_wav(path: str) -> str:
    if path.lower().endswith('.wav'):
        return path
    if shutil.which('ffmpeg') is None:
        raise RuntimeError('ffmpeg is required to convert uploaded voice recordings to WAV.')

    output_path = os.path.splitext(path)[0] + '.wav'
    subprocess.run(
        ['ffmpeg', '-y', '-i', path, '-ar', '16000', '-ac', '1', output_path],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return output_path


def _save_upload(upload_file, kind: str) -> str:
    if upload_file is None or upload_file.filename in (None, ''):
        raise ValueError(f'Missing {kind} file')
    os.makedirs(os.path.join(UPLOAD_DIR, kind), exist_ok=True)
    filename = secure_filename(upload_file.filename) or f'{kind}.bin'
    path = os.path.join(UPLOAD_DIR, kind, filename)
    upload_file.save(path)
    return path


def _user_exists(name: str) -> bool:
    db_path = os.path.join(BASE_DIR, 'face_database', 'embeddings.pickle')
    if not os.path.exists(db_path):
        return False
    import pickle
    with open(db_path, 'rb') as db_file:
        db = pickle.load(db_file)
    return name in db


@app.route('/health', methods=['GET'])
def health():
    return jsonify({'ok': True, 'service': 'vaultline-auth'})


@app.route('/api/auth/status', methods=['GET'])
def status():
    user_id = request.args.get('userId') or request.args.get('username') or 'demo-user'
    return jsonify({'enrolled': _user_exists(user_id), 'userId': user_id})


@app.route('/api/auth/enroll', methods=['POST'])
def enroll():
    try:
        user_id = (request.form.get('userId') or request.form.get('username') or 'demo-user').strip()
        face_file = request.files.get('face')
        voice_file = request.files.get('voice')

        if not user_id:
            raise ValueError('User id is required')

        if face_file is None:
            file_key = request.form.get('modality')
            if file_key == 'face':
                face_file = request.files.get('file')
        if voice_file is None:
            if request.form.get('modality') == 'voice':
                voice_file = request.files.get('file')

        if face_file is None:
            raise ValueError('Face image is required')
        if voice_file is None:
            raise ValueError('Voice sample is required')

        face_path = _save_upload(face_file, 'face')
        voice_path = _save_upload(voice_file, 'voice')
        voice_path = _ensure_wav(voice_path)
        if _user_exists(user_id):
            return jsonify({'ok': True, 'userId': user_id, 'message': 'User already enrolled', 'already_enrolled': True})
        add_user_from_files(user_id, face_path, [voice_path])
        return jsonify({'ok': True, 'userId': user_id, 'message': 'User enrolled successfully'})
    except ValueError as exc:
        error = str(exc)
        code = 'missing_file'
        if 'face' in error.lower() and 'required' in error.lower():
            code = 'missing_face'
        elif 'voice' in error.lower() and 'required' in error.lower():
            code = 'missing_voice'
        elif 'Exactly one face is required' in error:
            code = 'invalid_face'
        elif 'At least one voice sample is required' in error:
            code = 'invalid_voice'
        return jsonify({'ok': False, 'error': error, 'code': code}), 400
    except Exception as exc:  # pragma: no cover - API error path
        return jsonify({'ok': False, 'error': str(exc), 'code': 'internal_error'}), 400


@app.route('/api/auth/verify', methods=['POST'])
def verify():
    try:
        user_id = (request.form.get('userId') or request.form.get('username') or 'demo-user').strip()
        face_file = request.files.get('face')
        voice_file = request.files.get('voice')

        if face_file is None and request.form.get('modality') == 'face':
            face_file = request.files.get('file')
        if voice_file is None and request.form.get('modality') == 'voice':
            voice_file = request.files.get('file')

        if face_file is None:
            raise ValueError('Face image is required')
        if voice_file is None:
            raise ValueError('Voice sample is required')

        face_path = _save_upload(face_file, 'face')
        voice_path = _save_upload(voice_file, 'voice')
        voice_path = _ensure_wav(voice_path)
        if not _user_exists(user_id):
            return jsonify({'match': False, 'userId': user_id, 'ok': True, 'message': 'User not enrolled'})
        match = recognize_from_files(face_path, voice_path, expected_user=user_id)
        return jsonify({'match': bool(match), 'userId': user_id, 'ok': True})
    except ValueError as exc:
        error = str(exc)
        code = 'missing_file'
        if 'face' in error.lower() and 'required' in error.lower():
            code = 'missing_face'
        elif 'voice' in error.lower() and 'required' in error.lower():
            code = 'missing_voice'
        elif 'Exactly one face is required' in error:
            code = 'invalid_face'
        return jsonify({'ok': False, 'match': False, 'error': error, 'code': code}), 400
    except Exception as exc:  # pragma: no cover - API error path
        return jsonify({'ok': False, 'match': False, 'error': str(exc), 'code': 'internal_error'}), 400


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8001, debug=False, threaded=False)
