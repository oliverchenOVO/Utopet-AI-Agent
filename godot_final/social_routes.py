# social_routes.py — 村莊 AI 社交系統路由（整合自 Cluade GodotMapTest）

from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Optional, Dict, Any

from social_system import (
    SocialEngine, PersonalityProfile, PhysiologicalState,
    SchedulerBridge, ScheduledTask, MemoryLayer
)

router = APIRouter()

from pathlib import Path as _P
VILLAGE_DATA_DIR = str(_P(__file__).parent.parent / "Cluade GodotMapTest" / "GodotPY" / "data")

engine = SocialEngine(data_dir=VILLAGE_DATA_DIR)
bridges: Dict[str, SchedulerBridge] = {}


def _get_bridge(agent_id: str) -> SchedulerBridge:
    if agent_id not in bridges:
        mem = engine._memory.get(agent_id) or MemoryLayer(agent_id, VILLAGE_DATA_DIR + "/memory")
        bridges[agent_id] = SchedulerBridge(agent_id, engine, mem)
    return bridges[agent_id]


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
    apology_type:       str
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


@router.post("/register")
def register_agent(req: RegisterRequest) -> Dict[str, Any]:
    profile = PersonalityProfile(
        agent_id=req.agent_id,
        extroversion=req.extroversion,
        agreeableness=req.agreeableness,
        core_principles=req.core_principles
    )
    physio = PhysiologicalState(hunger=req.hunger, fatigue=req.fatigue)
    engine.register_agent(profile, physio)
    _get_bridge(req.agent_id)
    return {"success": True, "agent_id": req.agent_id}


@router.post("/physio")
def update_physio(req: PhysioUpdateRequest) -> Dict[str, Any]:
    from social_system.data_structures import PhysiologicalState
    engine.update_physio(req.agent_id, PhysiologicalState(req.hunger, req.fatigue))
    return {"success": True}


@router.post("/check")
def check_social(req: ProximityRequest) -> Dict[str, Any]:
    bridge = _get_bridge(req.initiator_id)
    result = bridge.on_proximity_trigger(req.target_id, req.distance, req.sim_minutes)
    return result


@router.post("/complete")
def complete_interaction(req: CompleteRequest) -> Dict[str, Any]:
    bridge = _get_bridge(req.agent_id)
    return bridge.complete_interaction(req.success)


@router.post("/event")
def process_event(req: EventRequest) -> Dict[str, Any]:
    return engine.process_subconscious_burst(
        req.observer_id, req.target_id,
        req.trigger_event, req.base_negativity
    )


@router.post("/apology")
def process_apology(req: ApologyRequest) -> Dict[str, Any]:
    return engine.process_apology(
        req.apologizer_id, req.target_id,
        req.apology_type, req.compensation_value
    )


@router.post("/mediate")
def mediate(req: MediateRequest) -> Dict[str, Any]:
    return engine.mediate_conflict(req.mediator_id, req.agent_a_id, req.agent_b_id)


@router.post("/sync_task")
def sync_task(req: TaskSyncRequest) -> Dict[str, Any]:
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
    resolved = engine.update_cold_war_timers(req.sim_minutes_elapsed)
    return {"cold_war_resolved": resolved}


@router.get("/relationship/{agent_a}/{agent_b}")
def get_relationship(agent_a: str, agent_b: str) -> Dict[str, Any]:
    rel = engine.get_relationship(agent_a, agent_b)
    return {
        "trust":          round(rel.trust, 2),
        "affection":      round(rel.affection, 2),
        "social_debt":    round(rel.social_debt, 2),
        "social_state":   rel.social_state.value,
        "cold_war_timer": rel.cold_war_timer
    }
