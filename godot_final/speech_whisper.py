from faster_whisper import WhisperModel
import sounddevice as sd
import numpy as np
import queue, time

_model = None

def get_model():
    global _model
    if _model is None:
        import os
        _local = "./faster-whisper-medium"
        _model_path = _local if os.path.isfile(f"{_local}/model.bin") else "Systran/faster-whisper-medium"
        print(f"⏳ 載入 faster-whisper medium（{_model_path}）...")
        _model = WhisperModel(_model_path, device="cuda", compute_type="float16")
        print("✅ 模型載入完成")
    return _model

def listen_once(timeout=10, device=None):
    """
    介面與原 speech_vosk.py 完全相同，Godot 不需改任何東西
    回傳: {"success": bool, "text": str, "error": str}
    """
    model = get_model()
    q = queue.Queue()
    SAMPLE_RATE = 16000

    def callback(indata, frames, time_info, status):
        q.put(indata.copy())

    print("🎤 聆聽中...")
    audio_chunks = []
    
    try:
        with sd.InputStream(samplerate=SAMPLE_RATE, channels=1,
                            dtype='float32', callback=callback,
                            blocksize=4000, device=device):
            start = time.time()
            silence_start = None
            SILENCE_THRESHOLD = 0.054
            SILENCE_DURATION = 1.5  # 靜音超過1.5秒就停止

            while True:
                try:
                    chunk = q.get(timeout=0.1)
                    audio_chunks.append(chunk)
                    
                    # 偵測靜音
                    rms = np.sqrt(np.mean(chunk**2))
                    if rms < SILENCE_THRESHOLD:
                        if silence_start is None:
                            silence_start = time.time()
                        elif time.time() - silence_start > SILENCE_DURATION and len(audio_chunks) > 5:
                            break
                    else:
                        silence_start = None
                        
                except queue.Empty:
                    pass
                
                if time.time() - start > timeout:
                    break

        if not audio_chunks:
            return {"success": False, "text": "", "error": "沒有收到音訊"}

        # 合併音訊並辨識
        audio = np.concatenate(audio_chunks, axis=0).flatten()
        segments, _ = model.transcribe(audio, language="zh",
                                        beam_size=5, vad_filter=True)
        text = "".join([seg.text for seg in segments]).strip()
        
        return {"success": True, "text": text}
        
    except Exception as e:
        return {"success": False, "text": "", "error": str(e)}