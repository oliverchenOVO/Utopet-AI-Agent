# speech_vosk.py
import sys
import os
import json
import queue
import sounddevice as sd
from vosk import Model, KaldiRecognizer

# --- 全局變數 ---
# 預設模型路徑，請確保資料夾存在
VOSK_MODEL_PATH = "vosk-model-small-cn-0.22"
_model_instance = None

def get_vosk_model():
    """單例模式獲取模型，避免重複加載"""
    global _model_instance
    if _model_instance is None:
        if not os.path.exists(VOSK_MODEL_PATH):
            print(f"❌ 錯誤：找不到 Vosk 模型路徑 '{VOSK_MODEL_PATH}'")
            return None
        
        print(f"⏳ 正在加載 Vosk 模型 ({VOSK_MODEL_PATH})...")
        try:
            _model_instance = Model(VOSK_MODEL_PATH)
            print("✅ Vosk 模型加載完成")
        except Exception as e:
            print(f"❌ Vosk 模型加載失敗: {e}")
            return None
    return _model_instance

def listen_once(timeout=5, device=None):
    """
    開啟麥克風聆聽一句話，直到停頓或超時。
    回傳:
        dict: {"success": bool, "text": str, "error": str}
    """
    model = get_vosk_model()
    if not model:
        return {"success": False, "error": "模型未加載"}

    q = queue.Queue()

    def callback(indata, frames, time, status):
        """音訊回調"""
        if status:
            print(status, file=sys.stderr)
        q.put(bytes(indata))

    print("🎤 正在聆聽中...")
    
    try:
        rec = KaldiRecognizer(model, 16000)
        # 這裡不使用 with ... as stream，便於控制異常流程
        stream = sd.RawInputStream(
            samplerate=16000, 
            blocksize=8000, 
            device=device,
            dtype='int16', 
            channels=1, 
            callback=callback
        )
        
        with stream:
            elapsed = 0
            check_interval = 0.5 # 每 0.5 秒檢查一次
            
            while True:
                try:
                    # 從 queue 拿數據
                    data = q.get(timeout=check_interval)
                    if rec.AcceptWaveform(data):
                        # 偵測到完整句子結束
                        res = json.loads(rec.Result())
                        text = res.get("text", "").strip()
                        if text:
                            return {"success": True, "text": text}
                except queue.Empty:
                    pass
                
                elapsed += check_interval
                if elapsed > timeout:
                    print("⏰ 聆聽超時")
                    # 超時強行結算
                    res = json.loads(rec.FinalResult())
                    text = res.get("text", "").strip()
                    return {"success": True, "text": text} # 就算超時也回傳當前聽到的
                    
    except Exception as e:
        return {"success": False, "error": str(e)}

# --- 以下保留原本的 class VoskStreamer (如果你的 GUI 版還需要用的話) ---
# 如果不需要舊的 PyQt5 程式碼，這裡可以刪除。
# 但為了兼容性，建議保留上面的 pure python 函數給 main.py 用。