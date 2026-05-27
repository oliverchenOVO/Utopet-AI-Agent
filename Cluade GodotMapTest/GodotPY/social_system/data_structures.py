# social_system/data_structures.py
# 所有資料結構定義 — 純 dataclass，不含業務邏輯

from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum
import time


# ─── 社交狀態機枚舉 ───────────────────────────────────────────

class SocialState(Enum):
    NORMAL    = "Normal"
    COLD_WAR  = "Cold_War"   # 冷戰，隨模擬時間自然衰減
    BLOCKED   = "Blocked"    # 封鎖，需極端事件才能解封


# ─── Agent 靜態設定 ──────────────────────────────────────────

@dataclass
class PersonalityProfile:
    agent_id:        str
    extroversion:    float        # 0.0(極內向) ~ 1.0(極外向)
    agreeableness:   float        # 0.0 ~ 1.0，影響調解意願
    core_principles: List[str]    # 觸發「核心原則衝突」的事件關鍵字
                                  # e.g. ["animal_abuse", "malicious_deception"]


# ─── 動態生理狀態（每幀/每分鐘更新）───────────────────────────

@dataclass
class PhysiologicalState:
    hunger:       float = 0.3    # 0.0(飽足) ~ 1.0(極餓)
    fatigue:      float = 0.3    # 0.0(充沛) ~ 1.0(精疲力竭)
    last_updated: float = field(default_factory=time.time)


# ─── 雙向關係紀錄 ────────────────────────────────────────────

@dataclass
class RelationshipRecord:
    agent_a:             str
    agent_b:             str
    trust:               float = 50.0   # 0~100，信任值
    affection:           float = 50.0   # 0~100，好感度
    social_debt:         float = 0.0    # 人情壓力：正值 = a 欠 b
    social_state:        SocialState = SocialState.NORMAL
    cold_war_timer:      float = 0.0    # 冷戰剩餘分鐘數（遊戲內時間）
    interaction_count:   int = 0
    last_interaction_ts: float = field(default_factory=time.time)  # real time


# ─── 記憶條目 ────────────────────────────────────────────────

@dataclass
class MemoryEntry:
    timestamp:    float
    participants: List[str]
    summary:      str
    emotion_tag:  str         # positive / negative / neutral / traumatic
    importance:   float       # 0.0 ~ 1.0，影響記憶壓縮保留優先度
    tags:         List[str]   # 可搜尋標籤：["conflict", "core_violation", ...]


# ─── 潛意識緩衝區條目 ────────────────────────────────────────

@dataclass
class SubconsciousEntry:
    timestamp:            float
    source_agent:         str
    incident_type:        str     # e.g. "minor_dishonesty", "unkind_remark"
    suppressed_negativity: float  # 被壓縮、未實際扣除的好感/信任傷害值
    raw_description:      str


# ─── 社交決策結果 ────────────────────────────────────────────

@dataclass
class SocialDecisionResult:
    should_interact:  bool
    v_social:         float    # 社交驅動力
    b_relationship:   float    # 關係加成
    v_schedule:       float    # 排程優先度（閾值）
    confidence:       float    # |combined - threshold| / threshold，0~∞
    invitation_type:  Optional[str] = None  # 邀約類型，供排程器決定轉場策略
