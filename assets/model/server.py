"""
Local Whisper + gesture recognition server.

Runs entirely on your laptop -- no API key, no billing, no cloud.
Your phone sends recorded audio to /transcribe (Whisper, unchanged) and
finished sign-language landmark sequences to /recognize-gesture (the
BiLSTM gesture classifier, moved here from on-device tflite_flutter).

Setup:
    pip install -r requirements.txt
    (adds tensorflow + numpy to whatever you already had for Whisper)

    Put these two files, unchanged from your Flutter assets, next to
    this script in a "model" folder:
        model/ASL_CITIZEN_200_BiLSTM.tflite
        model/class_list.txt

Run:
    uvicorn server:app --host 0.0.0.0 --port 8000

--host 0.0.0.0 is required (not 127.0.0.1) so your phone can reach this
server -- 127.0.0.1 only accepts connections from the laptop itself.
"""

import os
import tempfile

import numpy as np
import tensorflow as tf
from fastapi import Body, FastAPI, File, UploadFile
from fastapi.responses import JSONResponse
from faster_whisper import WhisperModel

app = FastAPI(title="Local Whisper + Gesture Server")

# ---------------------------------------------------------------------------
# Whisper (speech-to-text) -- unchanged.
# ---------------------------------------------------------------------------
model = WhisperModel("base", device="cpu", compute_type="int8")


@app.get("/health")
async def health():
    """Hit this from your phone's browser first to confirm the server
    is reachable before testing inside the app:
    http://<your-laptop-ip>:8000/health
    """
    return {"status": "ok"}


@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    suffix = os.path.splitext(file.filename or "")[1] or ".m4a"

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            content = await file.read()
            tmp.write(content)
            tmp_path = tmp.name

        segments, _info = model.transcribe(tmp_path, language="en")
        transcript = " ".join(segment.text.strip() for segment in segments).strip()

        return {"transcript": transcript}

    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})

    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


# ---------------------------------------------------------------------------
# Gesture recognition (BiLSTM classifier) -- new.
#
# The heavy per-frame work (camera capture, pose/hand landmark
# extraction, motion-based segmentation) all stays on-device in Flutter,
# same as before -- that needs to run in real time and doesn't belong
# on a network round trip. Only the final classification step, which
# already only ran once per finished sign (not per frame), moved here.
# ---------------------------------------------------------------------------
_GESTURE_SEQUENCE_LENGTH = 200
_GESTURE_FEATURES_PER_FRAME = 450
_GESTURE_NUM_CLASSES = 200

_MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "model")
_GESTURE_MODEL_PATH = os.path.join(_MODEL_DIR, "ASL_CITIZEN_200_BiLSTM.tflite")
_GESTURE_LABELS_PATH = os.path.join(_MODEL_DIR, "class_list.txt")


def _load_gesture_labels(path):
    """Same strict parsing/validation the Dart side used to do: parse
    both the index and label explicitly and verify the index matches
    the line's position, rather than trusting file order. A silently
    misordered class list would map every prediction to the wrong word
    without ever throwing an error, so this fails loudly instead.
    """
    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    labels = []
    for i, line in enumerate(lines):
        parts = line.split()
        if len(parts) < 2:
            raise ValueError(
                f'class_list.txt line {i + 1} ("{line}") doesn\'t match '
                f'the expected "<index> <LABEL>" format.'
            )
        try:
            parsed_index = int(parts[0])
        except ValueError:
            raise ValueError(
                f'class_list.txt line {i + 1}: expected a numeric index, found "{parts[0]}".'
            )
        if parsed_index != i:
            raise ValueError(
                f"class_list.txt is out of order at line {i + 1}: expected "
                f'index {i}, found "{parts[0]}".'
            )
        labels.append(" ".join(parts[1:]))

    if len(labels) != _GESTURE_NUM_CLASSES:
        raise ValueError(
            f"class_list.txt has {len(labels)} entries, expected {_GESTURE_NUM_CLASSES}."
        )
    return labels


_gesture_interpreter = None
_gesture_input_index = None
_gesture_output_index = None
_gesture_labels = None
_gesture_load_error = None

try:
    _gesture_interpreter = tf.lite.Interpreter(model_path=_GESTURE_MODEL_PATH)
    _gesture_interpreter.allocate_tensors()
    _gesture_input_index = _gesture_interpreter.get_input_details()[0]["index"]
    _gesture_output_index = _gesture_interpreter.get_output_details()[0]["index"]
    _gesture_labels = _load_gesture_labels(_GESTURE_LABELS_PATH)
    print(f"Gesture model loaded: {len(_gesture_labels)} classes.")
except Exception as e:
    _gesture_load_error = str(e)
    print(
        f"WARNING: gesture model not loaded ({e}). /recognize-gesture will "
        f"return 503 until ASL_CITIZEN_200_BiLSTM.tflite and class_list.txt "
        f"are placed in {_MODEL_DIR}/"
    )


def _softmax(logits: np.ndarray) -> np.ndarray:
    # Model outputs raw logits, same as the on-device version -- softmax
    # here so confidenceThreshold on the Dart side means what it looks
    # like it means.
    shifted = logits - np.max(logits)
    exp = np.exp(shifted)
    return exp / np.sum(exp)


@app.post("/recognize-gesture")
async def recognize_gesture(payload: dict = Body(...)):
    if _gesture_interpreter is None or _gesture_labels is None:
        return JSONResponse(
            status_code=503,
            content={
                "error": "Gesture model not loaded on the server. "
                f"({_gesture_load_error})"
            },
        )

    sequence = payload.get("sequence")
    if not isinstance(sequence, list) or len(sequence) != _GESTURE_SEQUENCE_LENGTH:
        got = len(sequence) if isinstance(sequence, list) else type(sequence).__name__
        return JSONResponse(
            status_code=400,
            content={
                "error": f"'sequence' must be a list of {_GESTURE_SEQUENCE_LENGTH} "
                f"frames, got {got}."
            },
        )

    try:
        arr = np.array(sequence, dtype=np.float32)
        expected_shape = (_GESTURE_SEQUENCE_LENGTH, _GESTURE_FEATURES_PER_FRAME)
        if arr.shape != expected_shape:
            return JSONResponse(
                status_code=400,
                content={"error": f"Expected shape {expected_shape}, got {arr.shape}."},
            )

        input_tensor = arr.reshape(1, *expected_shape)
        _gesture_interpreter.set_tensor(_gesture_input_index, input_tensor)
        _gesture_interpreter.invoke()
        logits = _gesture_interpreter.get_tensor(_gesture_output_index)[0]

        probs = _softmax(logits)
        best_index = int(np.argmax(probs))

        return {
            "label": _gesture_labels[best_index],
            "confidence": float(probs[best_index]),
        }

    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})
