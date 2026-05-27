# chat_handler.py - AI聊天處理模組
"""
負責與Ollama API通信的聊天處理器
"""
import requests
from typing import Tuple

# Ollama設定
OLLAMA_URL = "http://127.0.0.1:11434/api/generate"
MODEL_NAME = "qwen2.5:7b"

async def process_chat_message(message: str, temperature: float = 0.7, max_tokens: int = 4000) -> dict:
    """
    處理聊天消息並返回AI回應
    
    Args:
        message: 用戶消息
        temperature: 生成溫度
        max_tokens: 最大token數
    
    Returns:
        ChatResponse格式的字典
    """
    try:
        print(f"💬 收到訊息: {message}")
        
        payload = {
            "model": MODEL_NAME,
            "prompt": message,
            "stream": False,
            "options": {
                "temperature": temperature,
                "num_predict": max_tokens
            }
        }
        
        response = requests.post(OLLAMA_URL, json=payload, timeout=60)
        
        if response.status_code == 200:
            ai_reply = response.json().get('response', '').strip()
            print(f"✅ AI回應: {ai_reply[:100]}...")
            return {"success": True, "response": ai_reply, "error": ""}
        else:
            error_msg = f"Ollama Error: {response.status_code}"
            print(f"❌ {error_msg}")
            return {"success": False, "response": "", "error": error_msg}
            
    except requests.exceptions.ConnectionError:
        error_msg = "無法連接到Ollama服務，請確保Ollama正在運行"
        print(f"❌ {error_msg}")
        return {"success": False, "response": "", "error": error_msg}
    except requests.exceptions.Timeout:
        error_msg = "Ollama請求超時"
        print(f"❌ {error_msg}")
        return {"success": False, "response": "", "error": error_msg}
    except Exception as e:
        error_msg = str(e)
        print(f"❌ 錯誤: {error_msg}")
        return {"success": False, "response": "", "error": error_msg}


def test_ollama_connection() -> Tuple[bool, str]:
    """
    測試Ollama連接
    
    Returns:
        (success, message) 元組
    """
    try:
        response = requests.get("http://127.0.0.1:11434/api/tags", timeout=5)
        if response.status_code == 200:
            models = response.json().get("models", [])
            model_names = [m.get("name", "") for m in models]
            return True, f"已連接，可用模型: {model_names}"
        else:
            return False, f"連接失敗: HTTP {response.status_code}"
    except Exception as e:
        return False, f"連接錯誤: {str(e)}"


if __name__ == "__main__":
    # 測試連接
    success, msg = test_ollama_connection()
    print(f"Ollama連接測試: {'✅' if success else '❌'} {msg}")
