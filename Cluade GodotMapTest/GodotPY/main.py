# main.py - 精簡版API路由 v2.1
# 只保留@post路由定義，邏輯分離到各自的模組
import sys
import subprocess
import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional

# 引入功能模組
from speech_vosk import listen_once
from summarizer_plus import summarize_news_plus, summarize_article_plus
from chat_handler import process_chat_message
from calculator_handler import calculate_expression, open_system_calculator
from social_routes import router as social_router
from memory_routes import router as memory_router
from schedule_routes import router as schedule_router

app = FastAPI(title="Godot Python API", version="2.1.0")

# CORS設置
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(social_router,   prefix="/social",   tags=["Social System"])
app.include_router(memory_router,   prefix="/memory",   tags=["Memory System"])
app.include_router(schedule_router, prefix="/schedule", tags=["Schedule"])

# ===== 資料模型 =====

class ChatRequest(BaseModel):
    message: str
    temperature: float = 0.7
    max_tokens: int = 4000

class ChatResponse(BaseModel):
    success: bool
    response: str = ""
    error: str = ""

class SummaryRequest(BaseModel):
    title: str = ""
    text: str

class SummaryResponse(BaseModel):
    success: bool
    summary: str = ""
    points: List[str] = []
    error: str = ""

class SpeechResponse(BaseModel):
    success: bool
    text: str = ""
    error: str = ""

class SimpleResponse(BaseModel):
    success: bool
    message: str = ""
    error: str = ""

class CalculateRequest(BaseModel):
    expression: str

class CalculateResponse(BaseModel):
    success: bool
    result: str = ""
    error: str = ""

# ===== 路由定義 =====

@app.get("/")
async def root():
    return {
        "message": "Godot Python API 服務運行中",
        "status": "healthy",
        "version": "2.1.0"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "running",
        "features": ["chat", "ocr", "speech", "summarize", "calculator"]
    }

@app.post("/listen", response_model=SpeechResponse)
def listen_microphone():
    """語音識別"""
    result = listen_once(timeout=10)
    return SpeechResponse(
        success=result.get("success", False),
        text=result.get("text", ""),
        error=result.get("error", "")
    )

@app.post("/open_ocr", response_model=SimpleResponse)
async def open_ocr_window():
    """開啟OCR視窗"""
    try:
        subprocess.Popen([sys.executable, "ocr_gui_runner.py"])
        return SimpleResponse(success=True, message="OCR視窗啟動指令已發送")
    except Exception as e:
        return SimpleResponse(success=False, error=str(e))

@app.post("/chat", response_model=ChatResponse)
async def chat_with_ai(request: ChatRequest):
    """AI聊天"""
    return await process_chat_message(request.message, request.temperature, request.max_tokens)

@app.post("/summarize/news", response_model=SummaryResponse)
async def api_summarize_news(request: SummaryRequest):
    """新聞摘要"""
    try:
        summary, points = summarize_news_plus(request.title, request.text)
        return SummaryResponse(success=True, summary=summary, points=points)
    except Exception as e:
        return SummaryResponse(success=False, error=str(e))

@app.post("/summarize/article", response_model=SummaryResponse)
async def api_summarize_article(request: SummaryRequest):
    """文章摘要"""
    try:
        summary, points = summarize_article_plus(request.title, request.text)
        return SummaryResponse(success=True, summary=summary, points=points)
    except Exception as e:
        return SummaryResponse(success=False, error=str(e))

@app.post("/calculate", response_model=CalculateResponse)
async def calculate(request: CalculateRequest):
    """計算數學表達式"""
    result = calculate_expression(request.expression)
    return CalculateResponse(
        success=result.get("success", False),
        result=result.get("result", ""),
        error=result.get("error", "")
    )

@app.post("/open_calculator", response_model=SimpleResponse)
async def open_calculator():
    """打開系統計算器"""
    result = open_system_calculator()
    return SimpleResponse(
        success=result.get("success", False),
        message=result.get("message", ""),
        error=result.get("message", "") if not result.get("success", False) else ""
    )

# ===== 啟動入口 =====

if __name__ == "__main__":
    print("🚀 Godot Python API 服務器啟動: http://127.0.0.1:8000")
    print("📋 可用功能:")
    print("   /chat - AI聊天")
    print("   /listen - 語音識別")
    print("   /open_ocr - OCR文字識別")
    print("   /summarize/news - 新聞摘要")
    print("   /summarize/article - 文章摘要")
    print("   /calculate - 計算表達式")
    print("   /open_calculator - 打開系統計算器")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True, log_level="info")
