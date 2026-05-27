# llm_stream.py
"""
LLM 串流輸出模組（Ollama + yield 架構）

架構：
    語音 / 文字輸入
        ↓
    iter_chat_tokens()     ← 同步 generator，逐 token yield
        ↓
    aiter_chat_tokens()    ← async 包裝，丟進 thread pool
        ↓
    FastAPI StreamingResponse (SSE)
        ↓
    Godot / 前端即時顯示
"""

from __future__ import annotations

import asyncio
import json
import threading
from pathlib import Path
from typing import AsyncIterator, Iterator, Optional

import requests

# ─── 設定 ─────────────────────────────────────────────────

OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
MODEL_NAME = "qwen2.5:7b"

_BASE_DIR = Path(__file__).parent


# ─── 設定檔載入 ───────────────────────────────────────────

def _load_system_prompt() -> str:
    path = _BASE_DIR / "system_prompt.md"
    if not path.exists():
        raise FileNotFoundError(f"找不到 system_prompt.md：{path}")
    return path.read_text(encoding="utf-8")


def _load_tools() -> list:
    path = _BASE_DIR / "tools.json"
    if not path.exists():
        raise FileNotFoundError(f"找不到 tools.json：{path}")
    return json.loads(path.read_text(encoding="utf-8"))


# 啟動時載入一次
SYSTEM_PROMPT: str = _load_system_prompt()
TOOLS: list        = _load_tools()


def reload_config():
    """
    熱重載設定檔，不需重啟 server。
    呼叫方式：POST /admin/reload
    """
    global SYSTEM_PROMPT, TOOLS
    SYSTEM_PROMPT = _load_system_prompt()
    TOOLS         = _load_tools()
    print("[config] 已重新載入 system_prompt.md & tools.json")


# ─── 核心：同步串流 generator ──────────────────────────────

def iter_chat_tokens(
    user_message: str,
    history: list[dict] | None = None,
    temperature: float = 0.7,
    max_tokens: int = 512,
) -> Iterator[str]:
    """
    同步版串流 generator。
    向 Ollama 發送 stream=True，逐行解析 NDJSON，
    每解析到一個 token 就立即 yield 出去。

    用法：
        for token in iter_chat_tokens("你好"):
            print(token, end="", flush=True)

    參數：
        history: [{"role": "user"/"assistant", "content": "..."}]
    """
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    if history:
        messages.extend(history)
    messages.append({"role": "user", "content": user_message})

    payload = {
        "model": MODEL_NAME,
        "messages": messages,
        "stream": True,          # ← 關鍵：開啟串流
        "options": {
            "temperature": temperature,
            "num_predict": max_tokens,
        }
    }

    with requests.post(OLLAMA_URL, json=payload, stream=True, timeout=60) as resp:
        resp.raise_for_status()
        for raw_line in resp.iter_lines():
            if not raw_line:
                continue
            try:
                chunk = json.loads(raw_line)
            except json.JSONDecodeError:
                continue

            token = chunk.get("message", {}).get("content", "")
            if token:
                yield token          # ← 每個 token 立即 yield，不等全部完成

            if chunk.get("done"):
                break


# ─── 非同步包裝（給 FastAPI 用）────────────────────────────

async def aiter_chat_tokens(
    user_message: str,
    history: list[dict] | None = None,
    temperature: float = 0.7,
    max_tokens: int = 512,
) -> AsyncIterator[str]:
    """
    非同步版本。在 async def 端點裡使用。
    內部把同步 generator 丟進 thread pool，避免阻塞事件迴圈。

    用法：
        async for token in aiter_chat_tokens("你好"):
            yield token_to_sse(token)
    """
    loop = asyncio.get_event_loop()
    token_queue: asyncio.Queue[Optional[str]] = asyncio.Queue()

    def _producer():
        try:
            for token in iter_chat_tokens(user_message, history, temperature, max_tokens):
                loop.call_soon_threadsafe(token_queue.put_nowait, token)
        except Exception as e:
            loop.call_soon_threadsafe(token_queue.put_nowait, f"\n[ERROR] {e}")
        finally:
            loop.call_soon_threadsafe(token_queue.put_nowait, None)  # None = 結束哨兵

    threading.Thread(target=_producer, daemon=True, name="llm-stream").start()

    while True:
        token = await token_queue.get()
        if token is None:
            break
        yield token


# ─── SSE 格式化輔助 ───────────────────────────────────────

def token_to_sse(token: str) -> str:
    """
    把 token 包裝成 SSE 格式字串。

    Godot GDScript 解析範例：
        if line.begins_with("data: "):
            var token = line.substr(6).replace("\\\\n", "\\n")
            $Label.text += token
    """
    safe = token.replace("\n", "\\n")
    return f"event: token\ndata: {safe}\n\n"


def done_sse() -> str:
    """串流結束事件"""
    return "event: done\ndata: [DONE]\n\n"


def error_sse(msg: str) -> str:
    """錯誤事件"""
    safe = msg.replace("\n", " ")
    return f"event: error\ndata: {safe}\n\n"


# ─── 對話歷史管理（in-memory，依 session_id 隔離）──────────

class ConversationHistory:
    """
    簡易 in-memory 對話歷史。
    每個 session_id 各自維護一份 history list。
    """

    def __init__(self, max_turns: int = 10):
        self._store: dict[str, list[dict]] = {}
        self.max_turns = max_turns  # 一輪 = user + assistant 共 2 條訊息

    def get(self, session_id: str) -> list[dict]:
        return list(self._store.get(session_id, []))

    def add_user(self, session_id: str, text: str):
        self._store.setdefault(session_id, [])
        self._store[session_id].append({"role": "user", "content": text})
        self._trim(session_id)

    def add_assistant(self, session_id: str, text: str):
        self._store.setdefault(session_id, [])
        self._store[session_id].append({"role": "assistant", "content": text})
        self._trim(session_id)

    def clear(self, session_id: str):
        self._store.pop(session_id, None)

    def all_sessions(self) -> list[str]:
        return list(self._store.keys())

    def _trim(self, session_id: str):
        h = self._store[session_id]
        max_msgs = self.max_turns * 2
        if len(h) > max_msgs:
            self._store[session_id] = h[-max_msgs:]


# 全域單例，main_api.py import 後直接使用
conversation_history = ConversationHistory(max_turns=10)


# ─── CLI 快速測試 ─────────────────────────────────────────

if __name__ == "__main__":
    import sys

    prompt = " ".join(sys.argv[1:]) or "你好，介紹一下你自己"
    print(f"\n你：{prompt}")
    print("AI：", end="", flush=True)

    for tok in iter_chat_tokens(prompt):
        print(tok, end="", flush=True)

    print("\n✅ 完成")