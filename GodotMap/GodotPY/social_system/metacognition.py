# social_system/metacognition.py
# 元認知反思模組
# 觸發條件：連續社交失敗率 > 80%
# 反思路徑：檢索記憶標籤 → 判斷偏見歸因 → 決定行為策略

from typing import Dict, List, Optional
from .memory_system import MemoryLayer


class MetacognitionModule:
    WINDOW_SIZE       = 10     # 追蹤最近 N 次社交嘗試
    FAILURE_THRESHOLD = 0.80   # 超過此失敗率觸發反思
    OWN_FAULT_RATIO   = 0.50   # 超過此比例認定為自身偏見

    def __init__(self, agent_id: str, memory: MemoryLayer):
        self.agent_id = agent_id
        self.memory   = memory
        # True = success, False = failure
        self._interaction_log: List[bool] = []
        # 反思後是否已提交修正承諾
        self._correction_committed = False

    # ── 公開介面 ──────────────────────────────────────────────

    def record_outcome(self, success: bool) -> Optional[Dict]:
        """
        記錄一次社交結果。若觸發元認知，返回反思結果字典；否則返回 None。
        """
        self._interaction_log.append(success)
        if len(self._interaction_log) > self.WINDOW_SIZE:
            self._interaction_log.pop(0)

        failure_rate = self._current_failure_rate()

        if (len(self._interaction_log) >= self.WINDOW_SIZE
                and failure_rate > self.FAILURE_THRESHOLD
                and not self._correction_committed):
            return self._reflect(failure_rate)
        return None

    def commit_correction(self) -> None:
        """Agent 決定修正自我後，呼叫此方法標記。冷卻期內不再反思。"""
        self._correction_committed = True

    def reset_correction_flag(self) -> None:
        """一段時間後重置，允許下次反思"""
        self._correction_committed = False

    def get_failure_rate(self) -> float:
        return self._current_failure_rate()

    # ── 內部 ──────────────────────────────────────────────────

    def _current_failure_rate(self) -> float:
        if not self._interaction_log:
            return 0.0
        return self._interaction_log.count(False) / len(self._interaction_log)

    def _reflect(self, failure_rate: float) -> Dict:
        """
        反思流程：
          1. 撈取負面記憶標籤
          2. 計算自身歸因比例
          3. 返回行動指示（修正 or 堅守）
        """
        negative_memories = self.memory.search_by_tags(
            tags=["conflict", "rejection", "misunderstanding",
                  "core_violation", "self_bias", "own_mistake"],
            limit=20
        )

        if not negative_memories:
            # 無記憶依據 → 預設嘗試修正
            return self._build_result(failure_rate, is_own_bias=True,
                                      memory_count=0)

        own_fault_count = sum(
            1 for m in negative_memories
            if "self_bias" in m.tags or "own_mistake" in m.tags
        )
        own_fault_ratio = own_fault_count / len(negative_memories)
        is_own_bias     = own_fault_ratio >= self.OWN_FAULT_RATIO

        return self._build_result(failure_rate, is_own_bias,
                                  len(negative_memories))

    def _build_result(self, failure_rate: float, is_own_bias: bool,
                      memory_count: int) -> Dict:
        if is_own_bias:
            return {
                "triggered":         True,
                "failure_rate":      round(failure_rate, 3),
                "reflection_type":   "self_correction",
                "action":            "apologize_and_modify_behavior",
                "memory_evidence":   memory_count,
                "requires_llm":      True,
                # 傳入 LLM 的提示方向（外部組合成完整 prompt）
                "llm_prompt_hint":   (
                    f"{self.agent_id} 近期社交失敗率達 "
                    f"{failure_rate:.0%}，反思後認定原因為自身行為偏差，"
                    "請生成一段深刻的內心獨白，說明將如何改變並主動道歉。"
                )
            }
        else:
            return {
                "triggered":         True,
                "failure_rate":      round(failure_rate, 3),
                "reflection_type":   "principled_isolation",
                "action":            "accept_isolation_maintain_values",
                "memory_evidence":   memory_count,
                "requires_llm":      True,
                "llm_prompt_hint":   (
                    f"{self.agent_id} 近期社交失敗率達 "
                    f"{failure_rate:.0%}，反思後認定衝突源自他人偏見而非自身，"
                    "請生成一段堅守價值觀、接受孤立的內心獨白。"
                )
            }
