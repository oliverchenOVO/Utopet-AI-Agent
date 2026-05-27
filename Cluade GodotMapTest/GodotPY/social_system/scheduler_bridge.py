# social_system/scheduler_bridge.py
# SchedulerBridge — 將社交決策結果整合進 Godot Task_Scheduler
#
# 核心概念：「邀約轉場」
#   不直接中斷當前任務，而是透過語境自然的邀約讓 Agent 暫停排程。
#   原任務以 deferred_task 形式保留，社交結束後自動恢復。
#
# Godot 端呼叫流程：
#   1. 每幀距離檢測 → /social/check（HTTP POST）
#   2. 收到 should_interact=True → 播放邀約動畫、等待目標 Agent 回應
#   3. 社交結束 → /social/complete（HTTP POST）通知恢復排程

from dataclasses import dataclass, field
from typing import Dict, Optional
from .social_engine import SocialEngine
from .metacognition import MetacognitionModule
from .memory_system import MemoryLayer
from .data_structures import SocialDecisionResult


# ─── 排程任務的簡易表示 ──────────────────────────────────────

@dataclass
class ScheduledTask:
    name:            str
    target_location: str
    priority:        float        # 0~1，越高越不易被打斷
    start_sim_min:   float        # 遊戲內時間（分鐘）
    can_defer:       bool = True  # False = 不可中斷（如：睡覺、緊急任務）
    deferred:        bool = False


# ─── 邀約轉場腳本 ────────────────────────────────────────────

# 邀約類型 → Godot 端播放的動畫與等待時間設定
INVITATION_SCRIPTS: Dict[str, Dict] = {
    "meal_invitation": {
        "animation":        "wave_friendly",
        "dialogue_tag":     "invite_meal",        # Godot 端查表用
        "pause_minutes":    30.0,
        "interruptible":    False                 # 吃飯途中不再觸發社交
    },
    "casual_hangout": {
        "animation":        "wave_casual",
        "dialogue_tag":     "invite_hangout",
        "pause_minutes":    15.0,
        "interruptible":    True
    },
    "debt_repayment": {
        "animation":        "bow_slight",
        "dialogue_tag":     "repay_debt",
        "pause_minutes":    10.0,
        "interruptible":    False
    },
    "reconciliation_hint": {
        "animation":        "nod_hesitant",
        "dialogue_tag":     "cold_war_approach",
        "pause_minutes":    5.0,
        "interruptible":    True
    },
    "brief_greeting": {
        "animation":        "wave_quick",
        "dialogue_tag":     "greet_pass",
        "pause_minutes":    2.0,
        "interruptible":    True                  # 不暫停排程，僅播動畫
    },
}


# ─────────────────────────────────────────────────────────────
#  SchedulerBridge
# ─────────────────────────────────────────────────────────────

class SchedulerBridge:
    """
    每個 Agent 持有一個實例。

    公開方法：
      on_proximity_trigger()  → 距離觸發時調用，返回 Godot 可直接執行的指令
      complete_interaction()  → 社交結束後調用，恢復原排程
      tick()                  → 每個模擬 tick 調用，更新冷戰計時器等
    """

    def __init__(self, agent_id: str, engine: SocialEngine,
                 memory: MemoryLayer):
        self.agent_id = agent_id
        self.engine   = engine
        self._metacog = MetacognitionModule(agent_id, memory)

        self._current_task:  Optional[ScheduledTask] = None
        self._deferred_task: Optional[ScheduledTask] = None
        self._active_social: Optional[str] = None   # 當前社交對象 id

    # ── 設定當前任務（由 Godot tick_schedule 更新時同步）────────

    def set_current_task(self, task: ScheduledTask) -> None:
        self._current_task = task

    # ═══════════════════════════════════════════════════════════
    #  A. 距離觸發
    # ═══════════════════════════════════════════════════════════

    def on_proximity_trigger(
        self,
        target_id:   str,
        distance:    float,
        sim_minutes: float
    ) -> Dict:
        """
        返回 Godot 端可直接執行的指令字典：
          {
            "action": "greet_no_interrupt" | "accept_invitation" |
                      "decline_gracefully" | "skip",
            "script": {...},          # INVITATION_SCRIPTS 條目
            "decision_debug": {...}   # 供除錯 UI 顯示
          }
        """
        # 已在進行社交，忽略新觸發
        if self._active_social is not None:
            return {"action": "skip", "reason": "already_in_social"}

        decision: SocialDecisionResult = self.engine.evaluate_social_interaction(
            self.agent_id, target_id, sim_minutes, distance
        )

        debug = {
            "v_social":       round(decision.v_social, 2),
            "b_relationship": round(decision.b_relationship, 2),
            "v_schedule":     round(decision.v_schedule, 2),
            "confidence":     decision.confidence
        }

        if not decision.should_interact:
            return {"action": "skip", "reason": "formula_negative", "decision_debug": debug}

        inv_type = decision.invitation_type or "brief_greeting"
        script   = INVITATION_SCRIPTS[inv_type]

        # brief_greeting：不打斷排程
        if inv_type == "brief_greeting":
            return {
                "action":         "greet_no_interrupt",
                "script":         script,
                "decision_debug": debug
            }

        # 檢查當前任務是否可中斷
        if self._current_task and not self._current_task.can_defer:
            return {
                "action":         "decline_gracefully",
                "reason":         "task_not_deferrable",
                "decision_debug": debug
            }

        # 接受邀約：暫停當前任務
        if self._current_task:
            self._deferred_task         = self._current_task
            self._deferred_task.deferred = True

        self._active_social = target_id

        return {
            "action":            "accept_invitation",
            "invitation_type":   inv_type,
            "target_id":         target_id,
            "script":            script,
            "resume_after":      True,
            "decision_debug":    debug
        }

    # ═══════════════════════════════════════════════════════════
    #  B. 社交結束，恢復原排程
    # ═══════════════════════════════════════════════════════════

    def complete_interaction(self, success: bool) -> Dict:
        """
        社交對話結束後由 Godot 呼叫。
        記錄結果、觸發元認知檢查、恢復排程。
        """
        result: Dict = {"resumed_task": None, "metacognition": None}

        # 元認知記錄
        metacog_result = self._metacog.record_outcome(success)
        if metacog_result:
            result["metacognition"] = metacog_result

        # 恢復排程
        if self._deferred_task:
            self._current_task  = self._deferred_task
            self._deferred_task = None
            result["resumed_task"] = {
                "name":     self._current_task.name,
                "location": self._current_task.target_location
            }

        self._active_social = None
        return result

    # ═══════════════════════════════════════════════════════════
    #  C. 每 tick 更新（同步到 world.gd 的 _process）
    # ═══════════════════════════════════════════════════════════

    def tick(self, sim_minutes_elapsed: float) -> None:
        """
        傳入本次 tick 流逝的遊戲分鐘數，更新冷戰計時器。
        """
        self.engine.update_cold_war_timers(sim_minutes_elapsed)
