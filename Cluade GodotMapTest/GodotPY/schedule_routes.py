# schedule_routes.py — 日程建議 API
# POST /schedule/suggest_variant
#   接收：agent 名稱 + 當天生理數值
#   流程：讀取昨天故事 JSON → 查詢人際關係 → 組 prompt → 呼叫 Ollama → 回傳 variant_index
#   Fallback：Ollama 失敗時依數值（疲憊/心情）自動選擇

import json
import re
import requests
from pathlib import Path
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()

OLLAMA_URL   = "http://127.0.0.1:11434/api/generate"
OLLAMA_MODEL = "qwen2.5:1.5b"
STORIES_DIR  = Path(__file__).parent.parent / "stories"

# ── 各角色的日程變體描述（供 prompt 使用）──────────────────────
AGENT_VARIANTS: dict = {
    "Jack": {
        "role": "伐木工，個性勤奮踏實，喜歡在森林裡工作",
        "variants": [
            ("勤奮伐木", "按計畫砍完三棵樹，中午去市集吃飯，完整完成一天工作"),
            ("輕鬆砍樹", "只砍兩棵樹，空出下午去市集逛逛或到溪邊休息"),
            ("社交伐木", "早上先去市集找鄰居聊天，下午才進林子工作，順路拜訪朋友"),
        ],
    },
    "Mike": {
        "role": "礦工，沉默寡言，目前休假在小鎮閒逛",
        "variants": [
            ("市集巡禮", "沿著市集攤位一路閒逛，中午吃飯，下午去看動物"),
            ("自然漫步", "到樹林和溪邊走走，感受自然，順路看看農田"),
            ("鄰里閒晃", "在家附近和市集間慢慢打發時間，不走太遠"),
        ],
    },
    "Fin": {
        "role": "釣魚人，悠閒自在，享受湖邊寧靜的時光",
        "variants": [
            ("全天釣魚", "早上和下午都在溪邊垂釣，中間去市集吃飯"),
            ("半天釣魚", "只早上釣魚，下午去市集和動物區走走放鬆"),
            ("探索一日", "早上釣一段，下午去樹林找 Jack 或農田找 Buba 聊聊"),
        ],
    },
    "Buba": {
        "role": "農夫，熱心助人，對農田與動物充滿愛",
        "variants": [
            ("勤勞耕作", "完整照料所有農田，早上照顧動物，全天澆水耕地"),
            ("輕鬆農忙", "只做一半農活，下午去市集逛逛或到溪邊散心"),
            ("社交農夫", "早上先去市集找鄰居聊天，下午才回來做少量農事"),
        ],
    },
}


# ── Pydantic 模型 ─────────────────────────────────────────────

class ScheduleSuggestRequest(BaseModel):
    agent:      str
    hunger:     float
    fatigue:    float
    mood_value: float

class ScheduleSuggestResponse(BaseModel):
    variant_index: int
    variant_name:  str
    reason:        str = ""


# ── 輔助函式 ──────────────────────────────────────────────────

def _get_latest_story(agent: str) -> str:
    """讀取最新一篇日誌（JSON → 純文字）"""
    agent_dir = STORIES_DIR / agent
    if not agent_dir.exists():
        return ""
    files = sorted(agent_dir.glob("story_*.json"), reverse=True)
    if not files:
        return ""
    try:
        data    = json.loads(files[0].read_text(encoding="utf-8"))
        entries = data.get("entries", [])
        return "\n".join(entries)
    except Exception:
        return ""


def _get_relationship_summary(agent: str) -> str:
    """從 SocialEngine 查詢與其他角色的關係摘要"""
    try:
        from social_routes import engine
        from social_system.data_structures import SocialState
        others = [n for n in ["Jack", "Mike", "Fin", "Buba"] if n != agent]
        lines  = []
        for other in others:
            rel   = engine.get_relationship(agent, other)
            state = rel.social_state
            trust = rel.trust
            aff   = rel.affection
            if state == SocialState.COLD_WAR:
                lines.append(f"與 {other} 冷戰中")
            elif trust > 70 and aff > 70:
                lines.append(f"與 {other} 關係融洽（信任 {trust:.0f}、好感 {aff:.0f}）")
            elif trust < 35 or aff < 35:
                lines.append(f"與 {other} 關係疏離（信任 {trust:.0f}、好感 {aff:.0f}）")
        return "、".join(lines) if lines else "人際關係正常"
    except Exception:
        return ""


def _stats_fallback(agent: str, fatigue: float, mood_value: float) -> int:
    """LLM 失敗時的數值 fallback 選擇規則"""
    # Mike 休假，疲憊時傾向待在家附近（index 2），心情好才去大自然（index 1）
    if agent == "Mike":
        if fatigue > 60.0:
            return 2
        elif mood_value > 75.0:
            return 1
        return 0
    # 其他角色：疲憊 → 輕鬆版（index 1）；心情好 → 社交版（index 2）
    if fatigue > 60.0:
        return 1
    elif mood_value > 75.0:
        return 2
    return 0


def _build_prompt(agent: str, hunger: float, fatigue: float, mood_value: float) -> str:
    info = AGENT_VARIANTS.get(agent)
    if not info:
        return ""

    story         = _get_latest_story(agent)
    relationships = _get_relationship_summary(agent)

    if fatigue > 75:
        fatigue_desc = "非常疲憊、渾身酸痛"
    elif fatigue > 50:
        fatigue_desc = "有些疲憊"
    elif fatigue > 25:
        fatigue_desc = "略感疲倦"
    else:
        fatigue_desc = "精神飽滿"

    if mood_value > 80:
        mood_desc = "心情極佳、充滿活力"
    elif mood_value > 60:
        mood_desc = "心情不錯"
    elif mood_value < 40:
        mood_desc = "心情有些低落"
    else:
        mood_desc = "心情平穩"

    variants_text = ""
    for i, (name, desc) in enumerate(info["variants"]):
        letter = chr(ord("A") + i)
        variants_text += f"{letter}. {name}：{desc}\n"

    prompt  = "你是日程規劃助理。根據角色昨天的經歷和今天的狀態，選出最適合的日程方案。\n"
    prompt += "只輸出一個大寫字母（A、B 或 C），不輸出任何其他文字。\n\n"
    prompt += f"角色：{agent}（{info['role']}）\n"
    prompt += f"今日狀態：{fatigue_desc}，{mood_desc}\n"
    if relationships:
        prompt += f"人際關係：{relationships}\n"
    if story:
        prompt += f"\n昨天的日誌：\n{story}\n"
    prompt += f"\n可選日程方案：\n{variants_text}"
    prompt += "請根據角色昨天的經歷、身體狀態、人際互動，選出最自然合理的方案。\n"
    prompt += "只輸出方案字母："
    return prompt


# ── API 端點 ──────────────────────────────────────────────────

@router.post("/suggest_variant", response_model=ScheduleSuggestResponse)
def suggest_schedule_variant(req: ScheduleSuggestRequest):
    """
    讓 LLM 根據前一天故事、人際關係、生理狀態，推薦隔天的日程變體。
    LLM 失敗時自動降級到數值 fallback。
    """
    info = AGENT_VARIANTS.get(req.agent)
    if not info:
        return ScheduleSuggestResponse(variant_index=0, variant_name="預設", reason="未知角色")

    prompt = _build_prompt(req.agent, req.hunger, req.fatigue, req.mood_value)

    try:
        resp = requests.post(
            OLLAMA_URL,
            json={
                "model":   OLLAMA_MODEL,
                "prompt":  prompt,
                "stream":  False,
                "options": {"num_predict": 8, "temperature": 0.3},
            },
            timeout=25,
        )
        if resp.status_code == 200:
            raw = resp.json().get("response", "").strip().upper()
            m   = re.search(r"[ABC]", raw)
            if m:
                idx  = min(ord(m.group()) - ord("A"), len(info["variants"]) - 1)
                name = info["variants"][idx][0]
                print(f"[Schedule] {req.agent} LLM建議：{name}（回應：{raw}）")
                return ScheduleSuggestResponse(
                    variant_index=idx,
                    variant_name=name,
                    reason=f"LLM（{raw}）",
                )
    except Exception as e:
        print(f"[Schedule] {req.agent} Ollama呼叫失敗：{e}")

    # 數值 fallback
    idx  = _stats_fallback(req.agent, req.fatigue, req.mood_value)
    name = info["variants"][idx][0]
    print(f"[Schedule] {req.agent} 數值fallback → {name}（疲:{req.fatigue:.0f} 情:{req.mood_value:.0f}）")
    return ScheduleSuggestResponse(
        variant_index=idx,
        variant_name=name,
        reason="數值fallback",
    )
