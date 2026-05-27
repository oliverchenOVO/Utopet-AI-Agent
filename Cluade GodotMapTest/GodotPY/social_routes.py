# social_routes.py — FastAPI 路由，供 Godot 端透過 HTTP 呼叫
# 在 main.py 中加入：from social_routes import router as social_router
#                      app.include_router(social_router, prefix="/social")

from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Optional, Dict, Any

from social_system import (
    SocialEngine, PersonalityProfile, PhysiologicalState,
    SchedulerBridge, ScheduledTask, MemoryLayer
)

router = APIRouter()

# ─── 全域引擎實例（整個伺服器共享）──────────────────────────
engine = SocialEngine(data_dir="data")
bridges: Dict[str, SchedulerBridge] = {}   # agent_id → bridge


def _get_bridge(agent_id: str) -> SchedulerBridge:
    if agent_id not in bridges:
        mem = engine._memory.get(agent_id) or MemoryLayer(agent_id, "data/memory")
        bridges[agent_id] = SchedulerBridge(agent_id, engine, mem)
    return bridges[agent_id]


# ─── Pydantic 模型 ────────────────────────────────────────────

class RegisterRequest(BaseModel):
    agent_id:        str
    extroversion:    float
    agreeableness:   float
    core_principles: List[str]
    hunger:          float = 0.3
    fatigue:         float = 0.3

class PhysioUpdateRequest(BaseModel):
    agent_id: str
    hunger:   float
    fatigue:  float

class ProximityRequest(BaseModel):
    initiator_id: str
    target_id:    str
    distance:     float
    sim_minutes:  float

class CompleteRequest(BaseModel):
    agent_id: str
    success:  bool

class EventRequest(BaseModel):
    observer_id:     str
    target_id:       str
    trigger_event:   str
    base_negativity: float = 5.0

class ApologyRequest(BaseModel):
    apologizer_id:      str
    target_id:          str
    apology_type:       str    # verbal | material | public_statement
    compensation_value: float = 0.0

class MediateRequest(BaseModel):
    mediator_id: str
    agent_a_id:  str
    agent_b_id:  str

class TaskSyncRequest(BaseModel):
    agent_id:        str
    task_name:       str
    target_location: str
    priority:        float
    sim_minutes:     float
    can_defer:       bool = True

class TickRequest(BaseModel):
    sim_minutes_elapsed: float


# ─── 路由 ────────────────────────────────────────────────────

@router.post("/register")
def register_agent(req: RegisterRequest) -> Dict[str, Any]:
    """Agent 初始化時呼叫，登錄人格設定"""
    profile = PersonalityProfile(
        agent_id=req.agent_id,
        extroversion=req.extroversion,
        agreeableness=req.agreeableness,
        core_principles=req.core_principles
    )
    physio = PhysiologicalState(hunger=req.hunger, fatigue=req.fatigue)
    engine.register_agent(profile, physio)
    _get_bridge(req.agent_id)   # 預建 bridge
    return {"success": True, "agent_id": req.agent_id}


@router.post("/physio")
def update_physio(req: PhysioUpdateRequest) -> Dict[str, Any]:
    """更新 Agent 生理狀態（hunger/fatigue）"""
    from social_system.data_structures import PhysiologicalState
    engine.update_physio(req.agent_id, PhysiologicalState(req.hunger, req.fatigue))
    return {"success": True}


@router.post("/check")
def check_social(req: ProximityRequest) -> Dict[str, Any]:
    """
    距離觸發社交決策。
    Godot 在 proximity 事件時呼叫，根據返回的 action 決定 NPC 行為。
    """
    bridge = _get_bridge(req.initiator_id)
    result = bridge.on_proximity_trigger(
        req.target_id, req.distance, req.sim_minutes
    )
    return result


@router.post("/complete")
def complete_interaction(req: CompleteRequest) -> Dict[str, Any]:
    """社交對話結束後通知，自動恢復原排程"""
    bridge = _get_bridge(req.agent_id)
    return bridge.complete_interaction(req.success)


@router.post("/event")
def process_event(req: EventRequest) -> Dict[str, Any]:
    """
    觀察到目標行為時呼叫。
    非核心衝突 → 壓入潛意識；核心衝突 → 爆發清算。
    """
    return engine.process_subconscious_burst(
        req.observer_id, req.target_id,
        req.trigger_event, req.base_negativity
    )


@router.post("/apology")
def process_apology(req: ApologyRequest) -> Dict[str, Any]:
    """道歉/修復流程"""
    return engine.process_apology(
        req.apologizer_id, req.target_id,
        req.apology_type, req.compensation_value
    )


@router.post("/mediate")
def mediate(req: MediateRequest) -> Dict[str, Any]:
    """第三方 Agent 調解衝突"""
    return engine.mediate_conflict(
        req.mediator_id, req.agent_a_id, req.agent_b_id
    )


@router.post("/sync_task")
def sync_task(req: TaskSyncRequest) -> Dict[str, Any]:
    """Godot tick_schedule 切換任務時同步給 Bridge"""
    bridge = _get_bridge(req.agent_id)
    bridge.set_current_task(ScheduledTask(
        name=req.task_name,
        target_location=req.target_location,
        priority=req.priority,
        start_sim_min=req.sim_minutes,
        can_defer=req.can_defer
    ))
    return {"success": True}


@router.post("/tick")
def tick_all(req: TickRequest) -> Dict[str, Any]:
    """每個模擬 tick 呼叫一次，更新冷戰計時器"""
    resolved = engine.update_cold_war_timers(req.sim_minutes_elapsed)
    return {"cold_war_resolved": resolved}


@router.get("/relationship/{agent_a}/{agent_b}")
def get_relationship(agent_a: str, agent_b: str) -> Dict[str, Any]:
    """查詢兩 Agent 的關係值（供除錯 UI 顯示）"""
    rel = engine.get_relationship(agent_a, agent_b)
    return {
        "trust":       round(rel.trust, 2),
        "affection":   round(rel.affection, 2),
        "social_debt": round(rel.social_debt, 2),
        "social_state": rel.social_state.value,
        "cold_war_timer": rel.cold_war_timer
    }
