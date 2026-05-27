# memory_routes.py — FastAPI 路由，供 Godot 端存取記憶系統

from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Dict, Any

from memory_manager import save_conversation, get_context_for_conversation, get_agent_summary

router = APIRouter()


class DialogueLine(BaseModel):
    speaker: str
    content: str

class SaveConversationRequest(BaseModel):
    agent1:          str
    agent2:          str
    game_time:       str           # "08:30"
    dialogue_lines:  List[DialogueLine]

class ContextRequest(BaseModel):
    agent1: str
    agent2: str


@router.post("/save")
def save(req: SaveConversationRequest) -> Dict[str, Any]:
    """對話結束後，Godot 呼叫此端點儲存摘要"""
    lines = [{"speaker": l.speaker, "content": l.content} for l in req.dialogue_lines]
    return save_conversation(req.agent1, req.agent2, req.game_time, lines)


@router.post("/context")
def context(req: ContextRequest) -> Dict[str, Any]:
    """對話開始前，Godot 呼叫取得歷史記憶文字，注入 LLM prompt"""
    text = get_context_for_conversation(req.agent1, req.agent2)
    return {"context": text, "has_memory": len(text) > 0}


@router.get("/summary/{agent_id}")
def summary(agent_id: str) -> Dict[str, Any]:
    """查看某 Agent 的記憶摘要（除錯用）"""
    return get_agent_summary(agent_id)
