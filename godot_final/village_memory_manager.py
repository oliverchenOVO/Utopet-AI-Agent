# village_memory_manager.py — 村莊 Agent 對話記憶管理（整合自 GodotMap）
# 負責 Agent 間對話摘要與關係記錄，資料以 JSON 儲存於村莊專案目錄

import json
import os
from typing import Dict, List

from pathlib import Path as _P
MEMORY_ROOT = str(_P(__file__).parent.parent / "GodotMap" / "GodotPY" / "data" / "memory")
KNOWN_AGENTS = ["Jack", "Mike", "Fin", "Buba"]

TOPIC_KEYWORDS = {
    "天氣":   ["天氣", "下雨", "晴", "風", "冷", "熱", "溫度"],
    "工作":   ["伐木", "釣魚", "農田", "採礦", "作物", "收成", "砍樹", "澆水", "耕地"],
    "動物":   ["動物", "牲畜", "牛", "雞", "豬", "羊"],
    "食物":   ["吃飯", "午餐", "早餐", "晚餐", "食物", "餓", "好吃"],
    "生活":   ["休息", "睡覺", "散步", "放鬆", "閒逛", "無聊", "開心"],
    "人際":   ["你", "我", "他", "朋友", "鄰居", "幫忙", "謝謝"],
}

POSITIVE_WORDS = ["好", "棒", "開心", "愉快", "謝謝", "喜歡", "不錯", "順利", "豐收"]
NEGATIVE_WORDS = ["累", "煩", "難", "糟", "壞", "失敗", "擔心", "麻煩"]


def _conv_path(agent: str) -> str:
    return os.path.join(MEMORY_ROOT, agent, "conversations.json")

def _rel_path(agent: str) -> str:
    return os.path.join(MEMORY_ROOT, agent, "relationships.json")

def _ensure_dir(agent: str) -> None:
    os.makedirs(os.path.join(MEMORY_ROOT, agent), exist_ok=True)


def _load_conversations(agent: str) -> Dict:
    path = _conv_path(agent)
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"agent_id": agent, "entries": []}

def _save_conversations(agent: str, data: Dict) -> None:
    _ensure_dir(agent)
    with open(_conv_path(agent), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _load_relationships(agent: str) -> Dict:
    path = _rel_path(agent)
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    return {"agent_id": agent, "relationships": {}}

def _save_relationships(agent: str, data: Dict) -> None:
    _ensure_dir(agent)
    with open(_rel_path(agent), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _extract_topics(lines: List[Dict]) -> List[str]:
    full_text = " ".join(l.get("content", "") for l in lines)
    found = [topic for topic, keywords in TOPIC_KEYWORDS.items()
             if any(kw in full_text for kw in keywords)]
    return found if found else ["日常閒聊"]

def _detect_sentiment(lines: List[Dict]) -> str:
    full_text = " ".join(l.get("content", "") for l in lines)
    pos = sum(1 for w in POSITIVE_WORDS if w in full_text)
    neg = sum(1 for w in NEGATIVE_WORDS if w in full_text)
    if pos > neg:
        return "positive"
    if neg > pos:
        return "negative"
    return "neutral"

def _build_summary(name1: str, name2: str, topics: List[str], sentiment: str) -> str:
    mood_map = {"positive": "氣氛愉快", "negative": "有些沉重", "neutral": "氣氛平和"}
    return f"{name1} 與 {name2} 聊到了{'、'.join(topics)}，{mood_map[sentiment]}。"


def save_conversation(agent1: str, agent2: str, game_time: str, dialogue_lines: List[Dict]) -> Dict:
    topics    = _extract_topics(dialogue_lines)
    sentiment = _detect_sentiment(dialogue_lines)
    summary   = _build_summary(agent1, agent2, topics, sentiment)
    entry_id  = f"{game_time.replace(':', '')}_{agent1}_{agent2}"

    entry = {
        "id":           entry_id,
        "game_time":    game_time,
        "participants": [agent1, agent2],
        "line_count":   len(dialogue_lines),
        "topics":       topics,
        "sentiment":    sentiment,
        "summary":      summary,
    }

    for agent in [agent1, agent2]:
        data = _load_conversations(agent)
        data["entries"] = [e for e in data["entries"] if e["id"] != entry_id]
        data["entries"].append(entry)
        data["entries"] = data["entries"][-50:]
        _save_conversations(agent, data)

    _update_relationship(agent1, agent2, sentiment, game_time)
    _update_relationship(agent2, agent1, sentiment, game_time)

    return {"saved": True, "summary": summary, "topics": topics}


def _update_relationship(observer: str, target: str, sentiment: str, game_time: str) -> None:
    data = _load_relationships(observer)
    rels = data.setdefault("relationships", {})
    rec  = rels.setdefault(target, {
        "interaction_count": 0,
        "sentiment_history": [],
        "last_game_time":    "",
        "impression":        ""
    })
    rec["interaction_count"] += 1
    rec["last_game_time"]     = game_time
    rec["sentiment_history"]  = (rec["sentiment_history"] + [sentiment])[-10:]

    history  = rec["sentiment_history"]
    pos_rate = history.count("positive") / len(history)
    if pos_rate >= 0.7:
        rec["impression"] = f"與{target}相處愉快，對話輕鬆。"
    elif pos_rate <= 0.3:
        rec["impression"] = f"與{target}的對話有些沉悶或緊張。"
    else:
        rec["impression"] = f"與{target}維持普通的鄰里關係。"

    _save_relationships(observer, data)


def get_context_for_conversation(agent1: str, agent2: str, max_entries: int = 3) -> str:
    parts = []
    conv_data = _load_conversations(agent1)
    past = [e for e in conv_data["entries"] if agent2 in e.get("participants", [])][-max_entries:]

    if past:
        parts.append(f"【{agent1} 與 {agent2} 的歷史對話摘要】")
        for e in past:
            parts.append(f"  {e['game_time']} — {e['summary']}")

    rel_data = _load_relationships(agent1)
    rel = rel_data.get("relationships", {}).get(agent2)
    if rel and rel.get("impression"):
        parts.append(f"【{agent1} 對 {agent2} 的印象】{rel['impression']}")

    return "\n".join(parts) if parts else ""


def get_agent_summary(agent: str) -> Dict:
    conv = _load_conversations(agent)
    rels = _load_relationships(agent)
    return {
        "agent":               agent,
        "total_conversations": len(conv["entries"]),
        "known_agents":        list(rels.get("relationships", {}).keys()),
        "recent":              conv["entries"][-3:] if conv["entries"] else [],
        "relationships":       rels.get("relationships", {}),
    }
