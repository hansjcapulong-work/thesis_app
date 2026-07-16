"""
Local Whisper transcription server.

Runs entirely on your laptop -- no API key, no billing, no cloud.
Your phone sends recorded audio to this server over your shared WiFi
network, and this returns the transcribed text using an open-source
Whisper model running locally.

Setup:
    pip install -r requirements.txt

Run:
    uvicorn server:app --host 0.0.0.0 --port 8000

--host 0.0.0.0 is required (not 127.0.0.1) so your phone can reach this
server -- 127.0.0.1 only accepts connections from the laptop itself.
"""

import os
import tempfile

from fastapi import FastAPI, File, UploadFile
from fastapi.responses import JSONResponse
from faster_whisper import WhisperModel

app = FastAPI(title="Local Whisper Server")

# Model size options (bigger = more accurate but slower on CPU):
#   "tiny"   - fastest, lowest accuracy, good for quick testing
#   "base"   - good balance for a laptop CPU (recommended to start)
#   "small"  - noticeably better accuracy, still workable on CPU
#   "medium" / "large-v3" - best accuracy, needs a decent CPU or a GPU
#
# compute_type="int8" keeps CPU memory/speed reasonable. If you have an
# NVIDIA GPU with CUDA set up, you can set device="cuda" for a big speedup.
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
