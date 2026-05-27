# speech_whisper_stream.py
# 直接用 faster-whisper 內建 VAD，不需要額外裝 Silero
# pip install faster-whisper sounddevice numpy

from __future__ import annotations

import asyncio
import queue
import threading
import time
from typing import AsyncIterator, Callable, Optional

import numpy as np
import sounddevice as sd
from faster_whisper import WhisperModel

# ─── 常數 ─────────────────────────────────────────────────

SAMPLE_RATE     = 16_000
BLOCK_SIZE      = 4_000        # 250ms 一個音訊塊
SILENCE_RMS = 0.013       # RMS 靜音門限（略微提高，避免環境雜音誤判為語音）

# 說話中偵測到靜音幾塊後送推理（6×250ms = 1.5s）
# 調大一點避免短句被截斷；說完「可是」後 1.5s 就送出
SILENCE_BLOCKS_AFTER_SPEECH = 6

# 從頭到尾都沒說話，等幾塊後放棄（20×250ms = 5s）
MAX_LEADING_SILENCE_BLOCKS  = 20

# ─── Whisper 單例 ──────────────────────────────────────────

_model: Optional[WhisperModel] = None
_lock  = threading.Lock()

def get_model() -> WhisperModel:
    global _model
    if _model is None:
        with _lock:
            if _model is None:
                import os
                _local = "./faster-whisper-medium"
                _model_path = _local if os.path.isfile(f"{_local}/model.bin") else "Systran/faster-whisper-medium"
                print(f"⏳ 載入 faster-whisper medium（{_model_path}）...")
                _model = WhisperModel(
                    _model_path,
                    device="cuda",
                    compute_type="float16",
                )
                print("✅ 模型載入完成")
    return _model


# ─── 核心：雙 stream 架構 ──────────────────────────────────

class StreamingASR:
    """
    Stream-1（sounddevice）：持續捕捉音訊塊 → queue
    Stream-2（whisper）    ：
        - 偵測到「有語音 → 靜音」的邊界才送推理
        - 推理完一次就立即 stop，不繼續等待
        - 若一直沒有語音，超過 MAX_LEADING_SILENCE_BLOCKS 就放棄

    關鍵修正：
        舊版在 chunks.clear() 後繼續跑迴圈，造成第二次靜音又觸發、然後卡住。
        新版在 _transcribe 送出後直接 self._stop.set()，讓迴圈退出。
    """

    def __init__(self, on_partial: Optional[Callable[[str, bool], None]] = None):
        self.on_partial  = on_partial or (lambda text, is_final: None)
        self._q          = queue.Queue()
        self._stop       = threading.Event()
        self._asr_thread : Optional[threading.Thread] = None

    def start(self, device=None):
        self._stop.clear()
        self._asr_thread = threading.Thread(
            target=self._asr_loop, daemon=True, name="asr-loop"
        )
        self._asr_thread.start()

        self._stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype="float32",
            blocksize=BLOCK_SIZE,
            callback=self._audio_cb,
            device=device,
        )
        self._stream.start()
        print("🎤 串流聆聽中...")

    def stop(self):
        self._stop.set()
        if hasattr(self, "_stream"):
            try:
                self._stream.stop()
                self._stream.close()
            except Exception:
                pass
        if self._asr_thread:
            self._asr_thread.join(timeout=3)

    def _audio_cb(self, indata, frames, time_info, status):
        self._q.put(indata[:, 0].copy())

    def _asr_loop(self):
        model           = get_model()
        chunks          : list[np.ndarray] = []
        silence_blocks  = 0
        speech_detected = False   # ← 有沒有偵測到語音
        leading_silence = 0       # ← 開頭連續靜音計數

        while not self._stop.is_set():
            try:
                chunk = self._q.get(timeout=0.3)
            except queue.Empty:
                continue

            chunks.append(chunk)
            rms = float(np.sqrt(np.mean(chunk ** 2)))

            if rms >= SILENCE_RMS:
                # 有聲音
                speech_detected = True
                silence_blocks  = 0
                leading_silence = 0
            else:
                # 靜音
                silence_blocks += 1
                if not speech_detected:
                    leading_silence += 1

            # 開頭一直沒說話 → 放棄
            if leading_silence >= MAX_LEADING_SILENCE_BLOCKS:
                print("  [TIMEOUT] 沒有偵測到語音，結束錄音")
                self._stop.set()
                break

            # 說過話 + 現在靜音夠久 → 送推理，然後結束
            if speech_detected and silence_blocks >= SILENCE_BLOCKS_AFTER_SPEECH:
                audio = np.concatenate(chunks).astype(np.float32)
                self._transcribe(model, audio, is_final=True)
                self._stop.set()   # ← 推理完立刻停，不再繼續錄音
                break

    def _transcribe(self, model: WhisperModel, audio: np.ndarray, is_final: bool):
        if len(audio) < SAMPLE_RATE * 0.3:   # 低於 0.3s 忽略
            return
        t0 = time.perf_counter()
        segs, _ = model.transcribe(
            audio,
            language="zh",
            beam_size=1,                  # greedy，最快
            vad_filter=True,              # Whisper 內建 Silero VAD 過濾靜音段
            vad_parameters={"min_silence_duration_ms": 300},
            without_timestamps=True,
            condition_on_previous_text=False,
        )
        text = "".join(s.text for s in segs).strip()
        ms   = (time.perf_counter() - t0) * 1000
        if text:
            tag = "FINAL" if is_final else "partial"
            print(f"  [{tag}] {text!r}  ({ms:.0f}ms)")
            self.on_partial(text, is_final)


# ─── 向後相容：/listen 同步介面 ───────────────────────────

def listen_once(timeout: float = 10.0, device=None) -> dict:
    result_box: list[str] = []
    done = threading.Event()

    def on_result(text: str, is_final: bool):
        if is_final and text:
            result_box.append(text)
            done.set()

    asr = StreamingASR(on_partial=on_result)
    asr.start(device=device)
    done.wait(timeout=timeout)
    asr.stop()

    if result_box:
        return {"success": True, "text": result_box[-1], "error": ""}
    return {"success": False, "text": "", "error": "逾時或無語音輸入"}


# ─── SSE 串流介面：/listen_stream ─────────────────────────

async def listen_stream(timeout: float = 15.0, device=None) -> AsyncIterator[str]:
    loop     = asyncio.get_event_loop()
    sse_q: asyncio.Queue = asyncio.Queue()

    def on_result(text: str, is_final: bool):
        kind = "final" if is_final else "partial"
        loop.call_soon_threadsafe(sse_q.put_nowait, (kind, text))

    asr = StreamingASR(on_partial=on_result)
    asr.start(device=device)

    deadline = time.time() + timeout
    try:
        while time.time() < deadline:
            try:
                kind, text = sse_q.get_nowait()
                yield f"data: {kind}:{text}\n\n"
                if kind == "final":
                    break
            except asyncio.QueueEmpty:
                await asyncio.sleep(0.05)
    finally:
        asr.stop()
        yield "data: done\n\n"


# ─── CLI 測試 ─────────────────────────────────────────────

if __name__ == "__main__":
    import sys
    get_model()

    def show(text, is_final):
        tag = "✅" if is_final else "⌛"
        sys.stdout.write(f"\r{tag} {text:<70}\n" if is_final else f"\r⌛ {text:<70}")
        sys.stdout.flush()

    asr = StreamingASR(on_partial=show)
    asr.start()
    print("說話中... Ctrl+C 結束")
    try:
        while True:
            time.sleep(0.1)
    except KeyboardInterrupt:
        pass
    finally:
        asr.stop()
        print("\n👋 結束")