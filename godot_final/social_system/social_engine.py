# social_system/social_engine.py
# SocialEngine — 核心決策引擎
# 所有社交判定、潛意識爆發、修復與調解均在此處理
# 優先使用數值計算，LLM 僅在對話生成階段調用

import json
import math
import os
import time
from typing import Dict, List, Optional, Tuple

from .data_structures import (
    PersonalityProfile, PhysiologicalState, RelationshipRecord,
    SocialDecisionResult, SocialState, SubconsciousEntry, MemoryEntry
)
from .memory_system import MemoryLayer, SubconsciousBuffer


# ═════════════════════════════════════════════════════════════
#  SocialEngine
# ═════════════════════════════════════════════════════════════

class SocialEngine:
    """
    主要公開介面：
      evaluate_social_interaction()  → 決定是否觸發社交
      process_subconscious_burst()   → 處理負面事件（壓縮或爆發）
      process_apology()              → 道歉/修復流程
      mediate_conflict()             → 第三方 Agent 調解
      update_cold_war_timers()       → 每幀/每 tick 呼叫
    """

    # ── 權重常數（可透過 config 覆蓋）────────────────────────
    W_TRUST        = 0.40
    W_AFFECTION    = 0.40
    W_SOCIAL_DEBT  = 0.20
    BURST_AMP      = 1.5    # 潛意識爆發時的傷害放大係數
    V_BASE_SCHED   = 50.0   # 排程基礎優先度

    def __init__(self, data_dir: str = "data"):
        self._data_dir = data_dir
        self._profiles:      Dict[str, PersonalityProfile]  = {}
        self._physio:        Dict[str, PhysiologicalState]  = {}
        self._relationships: Dict[str, RelationshipRecord]  = {}
        self._memory:        Dict[str, MemoryLayer]         = {}
        self._subconscious:  Dict[str, SubconsciousBuffer]  = {}
        self._load_all_relationships()

    # ═══════════════════════════════════════════════════════
    #  1. 登錄 / 查詢
    # ═══════════════════════════════════════════════════════

    def register_agent(self, profile: PersonalityProfile,
                       physio: Optional[PhysiologicalState] = None) -> None:
        self._profiles[profile.agent_id] = profile
        self._physio[profile.agent_id] = physio or PhysiologicalState()
        self._memory[profile.agent_id] = MemoryLayer(
            profile.agent_id, os.path.join(self._data_dir, "memory")
        )

    def update_physio(self, agent_id: str, physio: PhysiologicalState) -> None:
        self._physio[agent_id] = physio

    def get_relationship(self, a: str, b: str) -> RelationshipRecord:
        key = self._rel_key(a, b)
        if key not in self._relationships:
            self._relationships[key] = RelationshipRecord(agent_a=a, agent_b=b)
        return self._relationships[key]

    # ═══════════════════════════════════════════════════════
    #  2. 核心函式 A — evaluate_social_interaction
    #     決策公式：V_social + B_relationship > V_schedule
    # ═══════════════════════════════════════════════════════

    def evaluate_social_interaction(
        self,
        initiator_id: str,
        target_id:    str,
        sim_minutes:  float,          # 當前遊戲內時間（分鐘）
        distance:     float           # 當前距離（pixel 或世界單位）
    ) -> SocialDecisionResult:
        """
        完整社交決策。純數值計算，不調用 LLM。

        返回 SocialDecisionResult，包含：
          - should_interact: bool
          - v_social, b_relationship, v_schedule（供除錯顯示）
          - invitation_type: 建議的邀約轉場類型
        """
        profile = self._profiles.get(initiator_id)
        physio  = self._physio.get(initiator_id, PhysiologicalState())
        rel     = self.get_relationship(initiator_id, target_id)

        # ── 計算三個子值 ────────────────────────────────────
        v_social  = self._calc_v_social(profile, rel)
        b_rel     = self._calc_b_relationship(rel)
        v_sched   = self._calc_v_schedule(physio)

        # ── 社交狀態阻斷 ─────────────────────────────────────
        if rel.social_state == SocialState.BLOCKED:
            return SocialDecisionResult(
                should_interact=False,
                v_social=v_social, b_relationship=b_rel, v_schedule=v_sched,
                confidence=1.0, invitation_type=None
            )

        # 冷戰期間排程阻力增加 50%
        effective_v_sched = v_sched * 1.5 if rel.social_state == SocialState.COLD_WAR else v_sched

        # ── 最終判定 ─────────────────────────────────────────
        combined       = v_social + b_rel
        gap            = combined - effective_v_sched
        should         = gap > 0
        confidence     = abs(gap) / max(effective_v_sched, 1.0)
        inv_type       = self._pick_invitation_type(rel, physio) if should else None

        return SocialDecisionResult(
            should_interact=should,
            v_social=v_social,
            b_relationship=b_rel,
            v_schedule=effective_v_sched,
            confidence=round(confidence, 3),
            invitation_type=inv_type
        )

    # ── 子計算：V_social ──────────────────────────────────────

    def _calc_v_social(self, profile: Optional[PersonalityProfile],
                       rel: RelationshipRecord) -> float:
        """
        外向者：社交飢渴隨時間增加（上限 1.5x base）
        內向者：社交慾望隨時間指數衰減（下限 0.1x base）
        base = extroversion * 60
        """
        if profile is None:
            return 30.0

        base = profile.extroversion * 60.0
        hours_since = (time.time() - rel.last_interaction_ts) / 3600.0
        hours_since = min(hours_since, 24.0)  # 上限 24 小時

        if profile.extroversion >= 0.5:
            # 外向：社交飢渴，最多 +50%
            hunger_bonus = min(0.5, hours_since * 0.04) * base
            return base + hunger_bonus
        else:
            # 內向：指數衰減，λ 隨內向程度加深
            lam = 0.5 + (0.5 - profile.extroversion) * 0.8
            return base * math.exp(-lam * hours_since / 8.0)

    # ── 子計算：B_relationship ────────────────────────────────

    def _calc_b_relationship(self, rel: RelationshipRecord) -> float:
        """
        B = trust * W_TRUST + affection * W_AFFECTION + debt * W_DEBT
        人情壓力 (debt > 0) 使發起方更想接觸以還情；debt < 0 則降低主動性。
        """
        debt_contribution = rel.social_debt * self.W_SOCIAL_DEBT
        return (rel.trust    * self.W_TRUST +
                rel.affection * self.W_AFFECTION +
                debt_contribution)

    # ── 子計算：V_schedule ────────────────────────────────────

    def _calc_v_schedule(self, physio: PhysiologicalState) -> float:
        """
        生理需求越高 → 排程優先度越高 → 越難被社交打斷
        飢餓貢獻最高 35，疲憊貢獻最高 25
        """
        hunger_w  = physio.hunger  ** 1.5 * 35.0   # 非線性，快餓死時急劇上升
        fatigue_w = physio.fatigue ** 1.2 * 25.0
        return self.V_BASE_SCHED + hunger_w + fatigue_w

    # ── 邀約類型選擇 ──────────────────────────────────────────

    def _pick_invitation_type(self, rel: RelationshipRecord,
                               physio: PhysiologicalState) -> str:
        if physio.hunger > 0.55:
            return "meal_invitation"      # 順便吃飯，自然轉場
        if rel.social_debt > 15.0:
            return "debt_repayment"       # 還人情，有明確動機
        if rel.affection > 72.0:
            return "casual_hangout"       # 閒逛、無目的交流
        if rel.social_state == SocialState.COLD_WAR:
            return "reconciliation_hint"  # 冷戰中試探性接觸
        return "brief_greeting"           # 短暫打招呼，不打斷排程

    # ═══════════════════════════════════════════════════════
    #  3. 核心函式 B — process_subconscious_burst
    #     非核心衝突 → 壓入潛意識；核心衝突 → 清算爆發
    # ═══════════════════════════════════════════════════════

    def process_subconscious_burst(
        self,
        observer_id:     str,
        target_id:       str,
        trigger_event:   str,          # 事件描述或關鍵字
        base_negativity: float = 5.0   # 非核心事件的基礎壓縮值
    ) -> Dict:
        """
        流程：
          1. 判斷是否觸發觀察者的核心原則。
          2a. 若非核心 → 壓入潛意識緩衝區，正常表面關係不變。
          2b. 若核心衝突 → 清算緩衝區 + 即時傷害，關係值斷崖下跌。
          3. 更新社交狀態機（Normal/Cold_War/Blocked）。
          4. 寫入重要記憶。
        """
        profile = self._profiles.get(observer_id)
        buf     = self._get_sub_buffer(observer_id, target_id)

        # ── 判斷核心原則衝突 ─────────────────────────────────
        is_core_violation = False
        if profile:
            is_core_violation = any(
                principle.lower() in trigger_event.lower()
                for principle in profile.core_principles
            )

        # ── 非核心：靜默壓縮 ─────────────────────────────────
        if not is_core_violation:
            entry = SubconsciousEntry(
                timestamp=time.time(),
                source_agent=target_id,
                incident_type=trigger_event,
                suppressed_negativity=base_negativity,
                raw_description=trigger_event
            )
            buf.push(entry)
            return {
                "burst_occurred":   False,
                "suppressed":       True,
                "buffer_total":     round(buf.peek_total(), 2),
                "entry_count":      buf.entry_count()
            }

        # ── 核心衝突爆發：清算緩衝區 ─────────────────────────
        suppressed_total = buf.clear()
        rel = self.get_relationship(observer_id, target_id)

        # 傷害計算
        immediate_dmg    = 30.0
        accumulated_dmg  = suppressed_total * self.BURST_AMP
        total_dmg        = min(100.0, immediate_dmg + accumulated_dmg)

        old_affection, old_trust = rel.affection, rel.trust
        rel.affection = max(0.0, rel.affection - total_dmg * 0.6)
        rel.trust     = max(0.0, rel.trust     - total_dmg * 0.4)

        # 更新狀態機
        if rel.affection < 10.0 or rel.trust < 10.0:
            rel.social_state   = SocialState.BLOCKED
            rel.cold_war_timer = 0.0
        elif rel.affection < 30.0 or rel.trust < 30.0:
            rel.social_state   = SocialState.COLD_WAR
            rel.cold_war_timer = 120.0   # 遊戲內 120 分鐘

        # 寫入高重要性記憶
        mem = self._memory.get(observer_id)
        if mem:
            mem.add(MemoryEntry(
                timestamp=time.time(),
                participants=[observer_id, target_id],
                summary=(f"{target_id} 觸發核心原則衝突「{trigger_event}」，"
                         f"關係值斷崖下跌（好感-{old_affection - rel.affection:.1f}，"
                         f"信任-{old_trust - rel.trust:.1f}）"),
                emotion_tag="traumatic",
                importance=0.95,
                tags=["core_violation", "relationship_crisis", target_id, trigger_event]
            ))

        self._save_relationship(rel)

        return {
            "burst_occurred":    True,
            "trigger":           trigger_event,
            "suppressed_released": round(suppressed_total, 2),
            "total_damage":      round(total_dmg, 2),
            "affection_drop":    round(old_affection - rel.affection, 2),
            "trust_drop":        round(old_trust     - rel.trust, 2),
            "new_social_state":  rel.social_state.value
        }

    # ═══════════════════════════════════════════════════════
    #  4. 社交修復 — 道歉
    # ═══════════════════════════════════════════════════════

    def process_apology(
        self,
        apologizer_id:      str,
        target_id:          str,
        apology_type:       str,     # "verbal" | "material" | "public_statement"
        compensation_value: float = 0.0
    ) -> Dict:
        rel = self.get_relationship(apologizer_id, target_id)

        if rel.social_state == SocialState.NORMAL:
            return {"success": False, "reason": "no_active_conflict"}

        # BLOCKED 狀態需要 public_statement + 高額補償
        if rel.social_state == SocialState.BLOCKED:
            if apology_type != "public_statement" or compensation_value < 50.0:
                return {"success": False,
                        "reason": "blocked_requires_public_statement_and_50+_compensation"}

        repair = {
            "verbal":            8.0,
            "material":          compensation_value * 0.8,
            "public_statement":  20.0 + compensation_value * 0.5
        }.get(apology_type, 8.0)

        rel.trust     = min(100.0, rel.trust     + repair * 0.4)
        rel.affection = min(100.0, rel.affection + repair * 0.6)

        if rel.social_state == SocialState.COLD_WAR:
            rel.cold_war_timer = max(0.0, rel.cold_war_timer - repair * 3.0)
            if rel.cold_war_timer <= 0.0:
                rel.social_state = SocialState.NORMAL

        if (rel.social_state == SocialState.BLOCKED
                and rel.trust > 25.0 and rel.affection > 25.0):
            rel.social_state   = SocialState.COLD_WAR
            rel.cold_war_timer = 60.0

        self._save_relationship(rel)
        return {
            "success":      True,
            "repair_amount": round(repair, 2),
            "new_trust":    round(rel.trust, 2),
            "new_affection": round(rel.affection, 2),
            "new_state":    rel.social_state.value
        }

    # ═══════════════════════════════════════════════════════
    #  5. 第三方調解 — Agent C 協助 A-B 修復關係
    # ═══════════════════════════════════════════════════════

    def mediate_conflict(
        self,
        mediator_id: str,
        agent_a_id:  str,
        agent_b_id:  str
    ) -> Dict:
        """
        條件：
          - mediator 的 agreeableness >= 0.6
          - mediator 與 A、B 的 trust 均 >= 50
        機制：
          - mediator 透支與 B 的信用（trust -= credit_spent）
          - A-B 關係提升
          - A 欠 mediator 人情（social_debt 增加）
        """
        m_profile = self._profiles.get(mediator_id)
        if not m_profile or m_profile.agreeableness < 0.6:
            return {"success": False, "reason": "mediator_not_agreeable_enough"}

        rel_ma = self.get_relationship(mediator_id, agent_a_id)
        rel_mb = self.get_relationship(mediator_id, agent_b_id)

        if rel_ma.trust < 50.0:
            return {"success": False, "reason": f"mediator_trust_with_{agent_a_id}_too_low"}
        if rel_mb.trust < 50.0:
            return {"success": False, "reason": f"mediator_trust_with_{agent_b_id}_too_low"}

        rel_ab = self.get_relationship(agent_a_id, agent_b_id)

        # mediator 透支與 B 的信任
        credit_spent   = 15.0 * m_profile.agreeableness
        rel_mb.trust   = max(0.0, rel_mb.trust - credit_spent)
        rel_mb.social_debt -= credit_spent        # B 欠 mediator

        # 提升 A-B 關係
        boost = m_profile.agreeableness * 20.0
        rel_ab.trust     = min(100.0, rel_ab.trust     + boost * 0.5)
        rel_ab.affection = min(100.0, rel_ab.affection + boost * 0.3)
        if rel_ab.social_state == SocialState.COLD_WAR:
            rel_ab.cold_war_timer *= 0.5

        # A 欠 mediator 人情
        rel_ma.social_debt += credit_spent * 0.8

        for rel in (rel_ma, rel_mb, rel_ab):
            self._save_relationship(rel)

        return {
            "success":        True,
            "credit_spent":   round(credit_spent, 2),
            "ab_boost":       round(boost, 2),
            "a_owes_mediator": round(rel_ma.social_debt, 2),
            "new_ab_state":   rel_ab.social_state.value
        }

    # ═══════════════════════════════════════════════════════
    #  6. 冷戰計時器更新（每 tick 呼叫）
    # ═══════════════════════════════════════════════════════

    def update_cold_war_timers(self, sim_minutes_elapsed: float) -> List[str]:
        """
        每個模擬 tick 呼叫，自動解除冷戰。
        返回本次從 Cold_War 轉回 Normal 的關係 key 列表。
        """
        resolved = []
        for key, rel in self._relationships.items():
            if rel.social_state == SocialState.COLD_WAR:
                rel.cold_war_timer -= sim_minutes_elapsed
                if rel.cold_war_timer <= 0.0:
                    rel.social_state   = SocialState.NORMAL
                    rel.cold_war_timer = 0.0
                    resolved.append(key)
                    self._save_relationship(rel)
        return resolved

    # ═══════════════════════════════════════════════════════
    #  7. 持久化輔助
    # ═══════════════════════════════════════════════════════

    def _rel_key(self, a: str, b: str) -> str:
        return f"{min(a, b)}_{max(a, b)}"

    def _get_sub_buffer(self, observer: str, target: str) -> SubconsciousBuffer:
        key = f"{observer}__{target}"
        if key not in self._subconscious:
            sub_dir = os.path.join(self._data_dir, "subconscious")
            self._subconscious[key] = SubconsciousBuffer(observer, target, sub_dir)
        return self._subconscious[key]

    def _rel_path(self, rel: RelationshipRecord) -> str:
        key = self._rel_key(rel.agent_a, rel.agent_b)
        return os.path.join(self._data_dir, "relationships", f"{key}.json")

    def _save_relationship(self, rel: RelationshipRecord) -> None:
        path = self._rel_path(rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = {
            "agent_a":             rel.agent_a,
            "agent_b":             rel.agent_b,
            "trust":               rel.trust,
            "affection":           rel.affection,
            "social_debt":         rel.social_debt,
            "social_state":        rel.social_state.value,
            "cold_war_timer":      rel.cold_war_timer,
            "interaction_count":   rel.interaction_count,
            "last_interaction_ts": rel.last_interaction_ts
        }
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def _load_all_relationships(self) -> None:
        rel_dir = os.path.join(self._data_dir, "relationships")
        if not os.path.isdir(rel_dir):
            return
        for fname in os.listdir(rel_dir):
            if not fname.endswith(".json"):
                continue
            with open(os.path.join(rel_dir, fname), "r", encoding="utf-8") as f:
                d = json.load(f)
            d["social_state"] = SocialState(d["social_state"])
            key = self._rel_key(d["agent_a"], d["agent_b"])
            self._relationships[key] = RelationshipRecord(**d)
