# summarizer_plus.py
"""
進階摘要模組
可替代 analyzer_api.py 裡的 _summarize_news / _summarize_article
"""

import re
import os
import json
from typing import List, Tuple, Optional

# --- 工具函數 ---
def _clean(s: str) -> str:
    return re.sub(r'\s+', ' ', s).strip()

def _sentences(txt: str) -> List[str]:
    parts = re.split(r'(?<=[。！？!?.])\s+|\n+', (txt or "").strip())
    return [p.strip() for p in parts if p.strip()]

# --- 加強版新聞摘要 ---
def summarize_news_plus(title: str, text: str) -> Tuple[str, List[str]]:
    """
    加強版新聞摘要：
    1. 嘗試用 LLM 生成摘要（若環境變數 NEWS_LLM_BASE 已設置）
    2. 否則用規則法挑選重點句 + 5W1H
    """
    base = os.getenv("NEWS_LLM_BASE")
    if base:
        try:
            import requests
            model = os.getenv("NEWS_LLM_MODEL", "qwen2.5:7b")
            api_key = os.getenv("NEWS_LLM_API_KEY", "not-needed")

            prompt = f"""你是新聞摘要助手。請用繁體中文輸出 JSON：
{{
 "summary": "3~5句摘要",
 "who": "...",
 "when": "...",
 "where": "...",
 "what": "...",
 "impact": "..."
}}
標題：{title}
正文：{text[:5000]}"""

            r = requests.post(
                f"{base}/chat/completions",
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "model": model,
                    "messages":[{"role":"user","content": prompt}],
                    "temperature": 0.2
                },
                timeout=20
            )
            r.raise_for_status()
            content = r.json()["choices"][0]["message"]["content"]
            j = json.loads(content)

            points = []
            if j.get("who"):    points.append("主體：" + j["who"])
            if j.get("when"):   points.append("時間：" + j["when"])
            if j.get("where"):  points.append("地點：" + j["where"])
            if j.get("what"):   points.append("事件：" + j["what"])
            if j.get("impact"): points.append("影響：" + j["impact"])
            return j.get("summary",""), points
        except Exception as e:
            print(f"[summarizer_plus] LLM 摘要失敗，退回規則法: {e}")

    # 規則法兜底
    sents = _sentences(text)
    top_sents = sents[:5] if sents else []
    summary = " ".join(top_sents) if top_sents else "（沒有可用的新聞內容）"

    # 簡單的 5W1H 抽取
    who  = re.search(r'(\w+)(?:表示|宣布|指出)', text)
    when = re.search(r'(\d{1,2}月\d{1,2}日|今天|昨日|近日)', text)
    where= re.search(r'(在\w+)', text)
    what = re.search(r'(宣布|指出|決定|批准|通過)(\w{2,20})', text)
    impact= re.search(r'(影響|導致|引發)(\w{2,20})', text)

    points = []
    if who:    points.append("主體：" + who.group(1))
    if when:   points.append("時間：" + when.group(1))
    if where:  points.append("地點：" + where.group(1))
    if what:   points.append("事件：" + what.group(1) + what.group(2))
    if impact: points.append("影響：" + impact.group(1) + impact.group(2))

    return summary, points


# --- 加強版文章摘要 ---
def summarize_article_plus(title: str, text: str) -> Tuple[str, List[str]]:
    """
    加強版一般文章摘要：
    - 優先用 LLM 產出段落式摘要
    - 沒有 LLM 時，取前幾段壓縮
    """
    base = os.getenv("ARTICLE_LLM_BASE")
    if base:
        try:
            import requests
            model = os.getenv("ARTICLE_LLM_MODEL", "qwen2.5:7b")
            api_key = os.getenv("ARTICLE_LLM_API_KEY", "not-needed")

            prompt = f"""你是文章總結助手。請用繁體中文輸出 JSON：
{{
 "summary": "150字以內的摘要",
 "keywords": ["...", "...", "..."]
}}
標題：{title}
正文：{text[:6000]}"""

            r = requests.post(
                f"{base}/chat/completions",
                headers={"Authorization": f"Bearer {api_key}"},
                json={
                    "model": model,
                    "messages":[{"role":"user","content": prompt}],
                    "temperature": 0.3
                },
                timeout=20
            )
            r.raise_for_status()
            content = r.json()["choices"][0]["message"]["content"]
            j = json.loads(content)

            points = []
            if "keywords" in j:
                points = ["關鍵詞：" + ", ".join(j["keywords"])]
            return j.get("summary",""), points
        except Exception as e:
            print(f"[summarizer_plus] LLM 摘要失敗，退回規則法: {e}")

    # 規則法兜底：取前幾段 + 關鍵詞
    paras = [p.strip() for p in text.split("\n") if p.strip()]
    summary = " ".join(paras[:3])[:180]
    words = re.findall(r'[\u4e00-\u9fff]{2,4}', text)
    top_keywords = list(dict.fromkeys(words))[:5]
    points = ["關鍵詞：" + ", ".join(top_keywords)] if top_keywords else []

    return summary, points
