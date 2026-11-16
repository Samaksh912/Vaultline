import tensorflow as tf
import numpy as np
import os
import sys
import pickle
import cv2
from numpy import genfromtxt

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FACENET_MODEL_PATH = os.path.join(BASE_DIR, 'facenet_model', 'model.h5')

try:
    from keras import backend as K
    from keras.models import load_model
except ImportError:
    from tensorflow.keras import backend as K
    from tensorflow.keras.models import load_model

K.set_image_data_format('channels_first')
# The FaceNet model in this project was trained with an older Keras Lambda-based format.
# TensorFlow 1.14/Keras 2.2 does not expose the TF 2.x API that newer code uses.
if hasattr(tf, 'keras') and hasattr(tf.keras, 'config') and hasattr(tf.keras.config, 'enable_unsafe_deserialization'):
    tf.keras.config.enable_unsafe_deserialization()
np.set_printoptions(threshold=sys.maxsize)

MODEL = None
MODEL_LOAD_ERROR = None


def _load_facenet_model():
    global MODEL, MODEL_LOAD_ERROR
    if MODEL is not None:
        return MODEL

    try:
        MODEL = load_model(
            FACENET_MODEL_PATH,
            custom_objects={'triplet_loss': triplet_loss},
            compile=False,
            safe_mode=False,
        )
        MODEL_LOAD_ERROR = None
        return MODEL
    except Exception as exc:  # pragma: no cover - depends on runtime compatibility
        MODEL_LOAD_ERROR = exc
        raise RuntimeError(
            'The legacy FaceNet H5 model could not be loaded in the current Python/Keras environment. '
            'This project was trained for an older Keras/TensorFlow stack. Install a compatible runtime '
            'or replace facenet_model/model.h5 with a model compatible with the current environment.'
        ) from exc


#provides 128 dim embeddings for face
def img_to_encoding(img):
    if MODEL is None:
        try:
            _load_facenet_model()
        except RuntimeError:
            raise

    img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    #converting img format to channel first
    img = np.around(np.transpose(img, (2,0,1))/255.0, decimals=12)

    x_train = np.array([img])

    #facial embedding from trained model
    embedding = MODEL.predict_on_batch(x_train)
    return embedding

#calculates triplet loss
def triplet_loss(y_true, y_pred, alpha = 0.2):
    anchor, positive, negative = y_pred[0], y_pred[1], y_pred[2]
    
    # triplet loss formula 
    pos_dist = tf.reduce_sum( tf.square(tf.subtract(y_pred[0], y_pred[1])) )
    neg_dist = tf.reduce_sum( tf.square(tf.subtract(y_pred[0], y_pred[2])) )
    basic_loss = pos_dist - neg_dist + alpha
    
    loss = tf.maximum(basic_loss, 0.0)
   
    return loss

# import dependencies for voice biometrics
import pyaudio
try:
    from IPython.display import Audio, display, clear_output
except ImportError:
    Audio = None
    display = None
    clear_output = None
import wave
from scipy.io.wavfile import read
import warnings
warnings.filterwarnings("ignore")

from sklearn import preprocessing
from sklearn.mixture import GaussianMixture
import python_speech_features as mfcc

# Compatibility alias for the legacy project API.
GMM = GaussianMixture


#Calculate and returns the delta of given feature vector matrix
def calculate_delta(array):
    rows,cols = array.shape
    deltas = np.zeros((rows,20))
    N = 2
    for i in range(rows):
        index = []
        j = 1
        while j <= N:
            if i-j < 0:
                first = 0
            else:
                first = i-j
            if i+j > rows -1:
                second = rows -1
            else:
                second = i+j
            index.append((second,first))
            j+=1
        deltas[i] = ( array[index[0][0]]-array[index[0][1]] + (2 * (array[index[1][0]]-array[index[1][1]])) ) / 10
    return deltas

#convert audio to mfcc features
def extract_features(audio,rate):    
    mfcc_feat = mfcc.mfcc(audio,rate, 0.025, 0.01,20,appendEnergy = True, nfft=1103)
    mfcc_feat = preprocessing.scale(mfcc_feat)
    delta = calculate_delta(mfcc_feat)

    #combining both mfcc features and delta
    combined = np.hstack((mfcc_feat,delta)) 
    return combined
