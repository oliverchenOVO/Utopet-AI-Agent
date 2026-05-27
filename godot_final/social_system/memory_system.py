# social_system/memory_system.py
# 記憶分層系統：一般記憶（可搜尋摘要）+ 潛意識緩衝區

import json
import os
import time
from dataclasses import asdict
from typing import List, Optional
from .data_structures import MemoryEntry, SubconsciousEntry


# ─────────────────────────────────────────────────────────────
#  MemoryLayer — 一般記憶，摘要式存儲，支援標籤搜尋
# ─────────────────────────────────────────────────────────────

class MemoryLayer:
    MAX_ENTRIES = 100           # 超過時壓縮低重要性記憶
    COMPRESS_TARGET = 80        # 壓縮後保留數量

    def __init__(self, agent_id: str, data_dir: str = "data/memory"):
        self.agent_id = agent_id
        self._path = os.path.join(data_dir, f"{agent_id}_memory.json")
        self.entries: List[MemoryEntry] = []
        self._load()

    # ── 公開介面 ──────────────────────────────────────────────

    def add(self, entry: MemoryEntry) -> None:
        self.entries.append(entry)
        if len(self.entries) > self.MAX_ENTRIES:
            self._compress()
        self._save()

    def search_by_tags(self, tags: List[str], limit: int = 10) -> List[MemoryEntry]:
        """返回包含任一標籤的記憶，按重要性降序"""
        matched = [m for m in self.entries if any(t in m.tags for t in tags)]
        matched.sort(key=lambda m: (m.importance, m.timestamp), reverse=True)
        return matched[:limit]

    def get_recent(self, n: int = 5) -> List[MemoryEntry]:
        return sorted(self.entries, key=lambda m: m.timestamp, reverse=True)[:n]

    # ── 內部方法 ──────────────────────────────────────────────

    def _compress(self) -> None:
        """保留高重要性條目，刪除低重要性舊條目"""
        self.entries.sort(key=lambda m: (m.importance, m.timestamp), reverse=True)
        self.entries = self.entries[:self.COMPRESS_TARGET]

    def _save(self) -> None:
        os.makedirs(os.path.dirname(self._path), exist_ok=True)
        with open(self._path, "w", encoding="utf-8") as f:
            json.dump([asdict(e) for e in self.entries], f, ensure_ascii=False, indent=2)

    def _load(self) -> None:
        if os.path.exists(self._path):
            with open(self._path, "r", encoding="utf-8") as f:
                raw = json.load(f)
            self.entries = [MemoryEntry(**r) for r in raw]


# ─────────────────────────────────────────────────────────────
#  SubconsciousBuffer — 潛意識緩衝區
#  存放「被過濾」的負面事件，核心衝突時一次性清算
# ─────────────────────────────────────────────────────────────

class SubconsciousBuffer:
    def __init__(self, observer_id: str, target_id: str,
                 data_dir: str = "data/subconscious"):
        self.observer_id = observer_id
        self.target_id = target_id
        self._path = os.path.join(data_dir, f"{observer_id}_{target_id}_sub.json")
        self.entries: List[SubconsciousEntry] = []
        self.total_suppressed: float = 0.0
        self._load()

    # ── 公開介面 ──────────────────────────────────────────────

    def push(self, entry: SubconsciousEntry) -> None:
        """壓入一條被過濾的負面記憶"""
        self.entries.append(entry)
        self.total_suppressed += entry.suppressed_negativity
        self._save()

    def clear(self) -> float:
        """
        爆發清算：清空緩衝區並返回累積的被壓縮傷害總值。
        調用方負責將此值乘以放大係數後扣除關係值。
        """
        released = self.total_suppressed
        self.entries = []
        self.total_suppressed = 0.0
        self._save()
        return released

    def peek_total(self) -> float:
        return self.total_suppressed

    def entry_count(self) -> int:
        return len(self.entries)

    # ── 內部方法 ──────────────────────────────────────────────

    def _save(self) -> None:
        os.makedirs(os.path.dirname(self._path), exist_ok=True)
        payload = {
            "total_suppressed": self.total_suppressed,
            "entries": [asdict(e) for e in self.entries]
        }
        with open(self._path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)

    def _load(self) -> None:
        if os.path.exists(self._path):
            with open(self._path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.total_suppressed = data.get("total_suppressed", 0.0)
            self.entries = [SubconsciousEntry(**e) for e in data.get("entries", [])]
