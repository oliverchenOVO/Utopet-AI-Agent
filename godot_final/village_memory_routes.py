# village_memory_routes.py — 村莊 Agent 對話記憶路由（掛載於 /village/memory）
# 現已使用統一 SQLite 資料庫取代 JSON 檔案

from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Dict, Any

from memory_helper import (
    save_agent_conversation,
    get_agent_conversation_context,
    get_agent_db_summary,
)

router = APIRouter()


class DialogueLine(BaseModel):
    speaker: str
    content: str

class SaveConversationRequest(BaseModel):
    agent1:         str
    agent2:         str
    game_time:      str
    dialogue_lines: List[DialogueLine]

class ContextRequest(BaseModel):
    agent1: str
    agent2: str


@router.post("/save")
def save(req: SaveConversationRequest) -> Dict[str, Any]:
    lines = [{"speaker": l.speaker, "content": l.content} for l in req.dialogue_lines]
    return save_agent_conversation(req.agent1, req.agent2, req.game_time, lines)


@router.post("/context")
def context(req: ContextRequest) -> Dict[str, Any]:
    text = get_agent_conversation_context(req.agent1, req.agent2)
    return {"context": text, "has_memory": len(text) > 0}


@router.get("/summary/{agent_id}")
def summary(agent_id: str) -> Dict[str, Any]:
    return get_agent_db_summary(agent_id)
