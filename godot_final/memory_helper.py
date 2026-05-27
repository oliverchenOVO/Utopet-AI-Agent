# memory_helper.py
"""
SQLite 長期記憶模組（含自動記憶、3/7 天老化、關機總結）

記憶分三種：
  - permanent：永久保留（名字、長期偏好、家人、工作、重要習慣等）
  - days_7   ：保留 7 天（近期計畫、最近在做的事、短期偏好等）
  - days_3   ：保留 3 天（今天心情、臨時狀態、短暫事件等）

另外有 memory_events 流水表：
  - 每句「非 tool 對話」即時判斷後，若值得記住，會寫入 memories 與 memory_events
  - server 關機時，main_api.py 會讀取今天的 memory_events，再統整成 permanent / days_7 / days_3
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

# ─── 設定 ─────────────────────────────────────────────────

DB_PATH = Path(__file__).parent / "pet_memory.db"

RETENTION_DAYS = {
    "permanent": None,
    "days_7": 7,
    "days_3": 3,
}

# 舊版 importance 相容
IMPORTANCE_ALIASES = {
    "important": "permanent",
    "permanent": "permanent",
    "normal": "days_7",
    "days_7": "days_7",
    "7d": "days_7",
    "short": "days_3",
    "days_3": "days_3",
    "3d": "days_3",
}

# 注入 system prompt 的最大筆數（permanent 優先）
MAX_INJECT = 30


# ─── 初始化 ───────────────────────────────────────────────

def _get_conn() -> sqlite3.Connection:
    """
    取得 SQLite 連線。
    check_same_thread=False：FastAPI 在不同 thread 呼叫，但每次用完就關閉。
    """
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def normalize_importance(importance: str | None) -> str:
    """把舊版/簡寫 importance 轉成目前使用的 permanent / days_7 / days_3。"""
    key = (importance or "days_7").strip().lower()
    return IMPORTANCE_ALIASES.get(key, "days_7")


def _now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def init_db():
    """
    建立資料表（若已存在則跳過），並順帶執行一次老化清理。
    在 FastAPI lifespan 啟動時呼叫。
    """
    with _get_conn() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS memories (
                key        TEXT PRIMARY KEY,
                importance TEXT NOT NULL DEFAULT 'days_7',
                value      TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        # 舊版欄位相容
        for col_sql in [
            "ALTER TABLE memories ADD COLUMN importance TEXT NOT NULL DEFAULT 'days_7'",
            "ALTER TABLE memories ADD COLUMN agent_name TEXT NOT NULL DEFAULT 'user'",
        ]:
            try:
                conn.execute(col_sql)
            except Exception:
                pass

        conn.execute("""
            CREATE TABLE IF NOT EXISTS memory_events (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                key         TEXT NOT NULL,
                value       TEXT NOT NULL,
                importance  TEXT NOT NULL DEFAULT 'days_7',
                source      TEXT NOT NULL DEFAULT 'auto',
                session_id  TEXT NOT NULL DEFAULT 'default',
                user_text   TEXT NOT NULL DEFAULT '',
                assistant_text TEXT NOT NULL DEFAULT '',
                created_at  TEXT NOT NULL
            )
        """)
        try:
            conn.execute("ALTER TABLE memory_events ADD COLUMN agent_name TEXT NOT NULL DEFAULT 'user'")
        except Exception:
            pass

        # 村莊 Agent 對話記憶表（取代 JSON 檔案）
        conn.execute("""
            CREATE TABLE IF NOT EXISTS agent_conversations (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                agent1       TEXT NOT NULL,
                agent2       TEXT NOT NULL,
                game_time    TEXT NOT NULL,
                topics       TEXT NOT NULL DEFAULT '',
                sentiment    TEXT NOT NULL DEFAULT 'neutral',
                summary      TEXT NOT NULL,
                line_count   INTEGER NOT NULL DEFAULT 0,
                created_at   TEXT NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS agent_relationships (
                observer         TEXT NOT NULL,
                target           TEXT NOT NULL,
                interaction_count INTEGER NOT NULL DEFAULT 0,
                sentiment_history TEXT NOT NULL DEFAULT '[]',
                last_game_time   TEXT NOT NULL DEFAULT '',
                impression       TEXT NOT NULL DEFAULT '',
                updated_at       TEXT NOT NULL,
                PRIMARY KEY (observer, target)
            )
        """)
        conn.commit()

    _migrate_old_importance()
    purge_expired()
    print(f"[memory] 資料庫初始化完成：{DB_PATH}")


def _migrate_old_importance():
    """把舊版 important / normal 轉成 permanent / days_7。"""
    with _get_conn() as conn:
        rows = conn.execute("SELECT key, importance FROM memories").fetchall()
        for row in rows:
            normalized = normalize_importance(row["importance"])
            if normalized != row["importance"]:
                conn.execute(
                    "UPDATE memories SET importance = ? WHERE key = ?",
                    (normalized, row["key"]),
                )
        conn.commit()


# ─── 老化清理 ──────────────────────────────────────────────

def purge_expired():
    """刪除所有 days_7 / days_3 中已過期的記憶。permanent 永遠不會被此函式刪除。"""
    now = datetime.now()
    deleted = 0

    with _get_conn() as conn:
        for importance, days in RETENTION_DAYS.items():
            if days is None:
                continue
            cutoff = (now - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
            cursor = conn.execute(
                "DELETE FROM memories WHERE importance = ? AND updated_at < ?",
                (importance, cutoff),
            )
            deleted += cursor.rowcount
        conn.commit()

    if deleted > 0:
        print(f"[memory] 老化清理：刪除 {deleted} 筆過期短期記憶")


# ─── 寫入 ─────────────────────────────────────────────────

def upsert_memory(
    key: str,
    value: str,
    importance: str = "days_7",
    *,
    source: str = "manual",
    session_id: str = "default",
    user_text: str = "",
    assistant_text: str = "",
    record_event: bool = True,
) -> str:
    """
    新增或更新一筆記憶（UPSERT）。

    importance:
      "permanent" / "important" → 永久保留
      "days_7" / "normal"       → 7 天後自動刪除
      "days_3"                  → 3 天後自動刪除
    """
    key = key.strip()
    value = value.strip()
    importance = normalize_importance(importance)

    if not key or not value:
        return "錯誤：key 和 value 都不能是空字串"

    now = _now_str()

    with _get_conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO memories (key, importance, value, updated_at) VALUES (?, ?, ?, ?)",
            (key, importance, value, now),
        )
        if record_event:
            conn.execute(
                """
                INSERT INTO memory_events
                    (key, value, importance, source, session_id, user_text, assistant_text, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (key, value, importance, source, session_id, user_text, assistant_text, now),
            )
        conn.commit()

    print(f"[memory] 已儲存 [{format_importance(importance)}] {key}: {value}")
    purge_expired()
    return f"已記住（{format_importance(importance)}）：{key} = {value}"


def delete_memory(key: str) -> str:
    """手動刪除指定 key 的記憶（不論 importance）。"""
    with _get_conn() as conn:
        cursor = conn.execute("DELETE FROM memories WHERE key = ?", (key.strip(),))
        conn.commit()
    if cursor.rowcount > 0:
        print(f"[memory] 已刪除：{key}")
        return f"已刪除記憶：{key}"
    return f"找不到記憶：{key}"


def set_importance(key: str, importance: str) -> str:
    """單獨更改某筆記憶的重要性，不改 value。"""
    importance = normalize_importance(importance)
    now = _now_str()
    with _get_conn() as conn:
        cursor = conn.execute(
            "UPDATE memories SET importance = ?, updated_at = ? WHERE key = ?",
            (importance, now, key.strip()),
        )
        conn.commit()
    if cursor.rowcount > 0:
        return f"已將「{key}」設為 {importance}"
    return f"找不到記憶：{key}"


# ─── 讀取 ─────────────────────────────────────────────────

def get_all_memories() -> list[dict]:
    """取得所有記憶。排序：personality > permanent > days_7 > days_3，同類型依更新時間由新到舊。"""
    purge_expired()
    with _get_conn() as conn:
        rows = conn.execute("""
            SELECT key, importance, value, updated_at
            FROM memories
            ORDER BY
                CASE
                    WHEN key LIKE 'personality:%' THEN 0
                    WHEN importance = 'permanent' THEN 1
                    WHEN importance = 'days_7' THEN 2
                    WHEN importance = 'days_3' THEN 3
                    ELSE 4
                END,
                updated_at DESC
        """).fetchall()
    return [dict(row) for row in rows]


def get_memory(key: str) -> Optional[str]:
    """查詢單一 key 的值，找不到回傳 None。"""
    with _get_conn() as conn:
        row = conn.execute(
            "SELECT value FROM memories WHERE key = ?", (key.strip(),)
        ).fetchone()
    return row["value"] if row else None


def get_today_memory_events() -> list[dict]:
    """取得今天所有被即時判斷後寫入 DB 的記憶事件。"""
    start = datetime.now().strftime("%Y-%m-%d 00:00:00")
    with _get_conn() as conn:
        rows = conn.execute("""
            SELECT id, key, value, importance, source, session_id, user_text, assistant_text, created_at
            FROM memory_events
            WHERE created_at >= ?
            ORDER BY created_at ASC
        """, (start,)).fetchall()
    return [dict(row) for row in rows]


def replace_today_auto_memories(items: list[dict]) -> int:
    """
    關機總結後，把今天 auto/summary 產生的短期候選重整成精簡版本。
    manual 來源保留，避免覆蓋使用者強制加入的 debug 記憶。
    """
    now = _now_str()
    today_start = datetime.now().strftime("%Y-%m-%d 00:00:00")

    with _get_conn() as conn:
        old_rows = conn.execute(
            "SELECT DISTINCT key FROM memory_events WHERE created_at >= ? AND source IN ('auto', 'summary')",
            (today_start,),
        ).fetchall()
        old_keys = [row["key"] for row in old_rows]
        conn.execute(
            "DELETE FROM memory_events WHERE created_at >= ? AND source IN ('auto', 'summary')",
            (today_start,),
        )
        for key in old_keys:
            conn.execute("DELETE FROM memories WHERE key = ?", (key,))
        for item in items:
            key = str(item.get("key", "")).strip()
            value = str(item.get("value", "")).strip()
            importance = normalize_importance(str(item.get("importance", "days_7")))
            if not key or not value:
                continue
            conn.execute(
                "INSERT OR REPLACE INTO memories (key, importance, value, updated_at) VALUES (?, ?, ?, ?)",
                (key, importance, value, now),
            )
            conn.execute(
                """
                INSERT INTO memory_events
                    (key, value, importance, source, session_id, user_text, assistant_text, created_at)
                VALUES (?, ?, ?, 'summary', 'shutdown', '', '', ?)
                """,
                (key, value, importance, now),
            )
        conn.commit()

    purge_expired()
    return len(items)


# ─── Prompt 注入 ───────────────────────────────────────────

def format_importance(importance: str) -> str:
    importance = normalize_importance(importance)
    if importance == "permanent":
        return "永久"
    if importance == "days_3":
        return "3天"
    return "7天"


def build_memory_block() -> str:
    """
    把記憶組成文字區塊，準備插入 system prompt。
    personality: 前綴的記憶獨立成一個區塊排最前面，
    其餘記憶照 permanent > days_7 > days_3 排序，短期記憶標示剩餘天數。
    """
    memories = get_all_memories()[:MAX_INJECT]
    if not memories:
        return ""

    now = datetime.now()
    personality_lines = []
    memory_lines = []

    for m in memories:
        importance = normalize_importance(m["importance"])
        key = m["key"]

        if key.startswith("personality:"):
            display_key = key[len("personality:"):]
            personality_lines.append(f"{display_key}：{m['value']}")
        else:
            if importance == "permanent":
                prefix = "[永久]"
                suffix = ""
            else:
                updated = datetime.strptime(m["updated_at"], "%Y-%m-%d %H:%M:%S")
                days = RETENTION_DAYS[importance] or 7
                expire = updated + timedelta(days=days)
                days_left = max(1, (expire - now).days + 1)
                prefix = "[短期]"
                suffix = f"（約 {days_left} 天後過期）"
            memory_lines.append(f"{prefix} {key}：{m['value']}{suffix}")

    blocks = []

    if personality_lines:
        blocks.append("# 你目前的個性特徵（透過相處自然演化，融入說話方式，不要逐條念出）")
        blocks.extend(personality_lines)

    if memory_lines:
        if blocks:
            blocks.append("")
        blocks.append("# 關於使用者的記憶（請在對話中自然運用，不要逐條念出）")
        blocks.extend(memory_lines)

    return "\n".join(blocks)


def inject_memory_to_prompt(base_prompt: str) -> str:
    """把記憶區塊附加到 system prompt 末尾。"""
    memory_block = build_memory_block()
    if not memory_block:
        return base_prompt
    return f"{base_prompt}\n\n{memory_block}"


# ─── 村莊 Agent 記憶（SQLite 版）────────────────────────────

import json as _json

def upsert_agent_memory(agent_name: str, key: str, value: str, importance: str = "days_7") -> str:
    """寫入或更新特定 Agent 的記憶（用 agent:{name}:{key} 格式存入共用 memories 表）。"""
    full_key   = f"agent:{agent_name}:{key.strip()}"
    importance = normalize_importance(importance)
    now        = _now_str()
    with _get_conn() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO memories (key, importance, value, updated_at, agent_name) VALUES (?, ?, ?, ?, ?)",
            (full_key, importance, value.strip(), now, agent_name),
        )
        conn.commit()
    return f"[agent:{agent_name}] 已記住：{key}"


def get_agent_memories(agent_name: str) -> list[dict]:
    """取得特定 Agent 的所有記憶。"""
    purge_expired()
    prefix = f"agent:{agent_name}:"
    with _get_conn() as conn:
        rows = conn.execute(
            "SELECT key, importance, value, updated_at FROM memories WHERE agent_name = ? ORDER BY updated_at DESC",
            (agent_name,),
        ).fetchall()
    return [
        {**dict(row), "short_key": row["key"].removeprefix(prefix)}
        for row in rows
    ]


def get_agent_memory_context(agent_name: str, max_items: int = 15) -> str:
    """格式化 Agent 記憶，供注入 LLM system prompt。"""
    memories = get_agent_memories(agent_name)[:max_items]
    if not memories:
        return ""
    lines = [f"# {agent_name} 的記憶與經歷"]
    for m in memories:
        lines.append(f"- {m['short_key']}：{m['value']}")
    return "\n".join(lines)


# ─── 村莊 Agent 對話記憶（SQLite 取代 JSON）─────────────────

def save_agent_conversation(
    agent1: str, agent2: str, game_time: str,
    dialogue_lines: list[dict],
) -> dict:
    """儲存兩個 Agent 的對話摘要到 SQLite。"""
    TOPIC_KEYWORDS = {
        "天氣": ["天氣","下雨","晴","風","冷","熱","溫度"],
        "工作": ["伐木","釣魚","農田","採礦","作物","收成","砍樹","澆水","耕地"],
        "動物": ["動物","牲畜","牛","雞","豬","羊"],
        "食物": ["吃飯","午餐","早餐","晚餐","食物","餓","好吃"],
        "生活": ["休息","睡覺","散步","放鬆","閒逛","無聊","開心"],
        "人際": ["你","我","他","朋友","鄰居","幫忙","謝謝"],
    }
    POSITIVE = ["好","棒","開心","愉快","謝謝","喜歡","不錯","順利","豐收"]
    NEGATIVE = ["累","煩","難","糟","壞","失敗","擔心","麻煩"]

    full_text = " ".join(l.get("content","") for l in dialogue_lines)
    topics    = [t for t, kws in TOPIC_KEYWORDS.items() if any(kw in full_text for kw in kws)] or ["日常閒聊"]
    pos       = sum(1 for w in POSITIVE if w in full_text)
    neg       = sum(1 for w in NEGATIVE if w in full_text)
    sentiment = "positive" if pos > neg else ("negative" if neg > pos else "neutral")
    mood_map  = {"positive":"氣氛愉快","negative":"有些沉重","neutral":"氣氛平和"}
    summary   = f"{agent1} 與 {agent2} 聊到了{'、'.join(topics)}，{mood_map[sentiment]}。"
    now       = _now_str()

    with _get_conn() as conn:
        conn.execute(
            """INSERT INTO agent_conversations (agent1, agent2, game_time, topics, sentiment, summary, line_count, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (agent1, agent2, game_time, ",".join(topics), sentiment, summary, len(dialogue_lines), now),
        )
        for agent, other in [(agent1, agent2), (agent2, agent1)]:
            row = conn.execute(
                "SELECT sentiment_history, interaction_count FROM agent_relationships WHERE observer=? AND target=?",
                (agent, other),
            ).fetchone()
            if row:
                history = _json.loads(row["sentiment_history"])
                count   = row["interaction_count"] + 1
            else:
                history = []
                count   = 1
            history = (history + [sentiment])[-10:]
            pos_rate = history.count("positive") / len(history)
            impression = (
                f"與{other}相處愉快，對話輕鬆。" if pos_rate >= 0.7 else
                f"與{other}的對話有些沉悶或緊張。" if pos_rate <= 0.3 else
                f"與{other}維持普通的鄰里關係。"
            )
            conn.execute(
                """INSERT OR REPLACE INTO agent_relationships
                   (observer, target, interaction_count, sentiment_history, last_game_time, impression, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (agent, other, count, _json.dumps(history), game_time, impression, now),
            )
        conn.commit()

    return {"saved": True, "summary": summary, "topics": topics}


def get_agent_conversation_context(agent1: str, agent2: str, max_entries: int = 3) -> str:
    """取得兩個 Agent 的歷史對話摘要，供注入 LLM prompt。"""
    parts = []
    with _get_conn() as conn:
        rows = conn.execute(
            """SELECT game_time, summary FROM agent_conversations
               WHERE (agent1=? AND agent2=?) OR (agent1=? AND agent2=?)
               ORDER BY created_at DESC LIMIT ?""",
            (agent1, agent2, agent2, agent1, max_entries),
        ).fetchall()
        rel = conn.execute(
            "SELECT impression FROM agent_relationships WHERE observer=? AND target=?",
            (agent1, agent2),
        ).fetchone()

    if rows:
        parts.append(f"【{agent1} 與 {agent2} 的歷史對話摘要】")
        for row in reversed(rows):
            parts.append(f"  {row['game_time']} — {row['summary']}")
    if rel and rel["impression"]:
        parts.append(f"【{agent1} 對 {agent2} 的印象】{rel['impression']}")

    return "\n".join(parts)


def get_agent_db_summary(agent: str) -> dict:
    """取得 Agent 的記憶摘要（除錯用）。"""
    with _get_conn() as conn:
        total = conn.execute(
            "SELECT COUNT(*) as c FROM agent_conversations WHERE agent1=? OR agent2=?",
            (agent, agent),
        ).fetchone()["c"]
        rels = conn.execute(
            "SELECT target, impression, interaction_count FROM agent_relationships WHERE observer=?",
            (agent,),
        ).fetchall()
        recent = conn.execute(
            """SELECT game_time, summary FROM agent_conversations
               WHERE agent1=? OR agent2=? ORDER BY created_at DESC LIMIT 3""",
            (agent, agent),
        ).fetchall()
    return {
        "agent":               agent,
        "total_conversations": total,
        "relationships":       {r["target"]: {"impression": r["impression"], "count": r["interaction_count"]} for r in rels},
        "recent":              [dict(r) for r in recent],
    }
