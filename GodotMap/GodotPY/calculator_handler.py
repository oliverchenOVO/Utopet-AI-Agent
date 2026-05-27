# calculator_handler.py - 計算器處理模組
"""
提供兩種計算方式：
1. Python內建計算（安全eval）
2. 打開系統計算器
"""
import subprocess
import re
import math
from typing import Tuple

# 安全的數學函數白名單
SAFE_MATH_FUNCTIONS = {
    'abs': abs,
    'round': round,
    'min': min,
    'max': max,
    'sum': sum,
    'pow': pow,
    # math模組函數
    'sqrt': math.sqrt,
    'sin': math.sin,
    'cos': math.cos,
    'tan': math.tan,
    'log': math.log,
    'log10': math.log10,
    'exp': math.exp,
    'floor': math.floor,
    'ceil': math.ceil,
    'pi': math.pi,
    'e': math.e,
}


def calculate_expression(expression: str) -> dict:
    """
    安全計算數學表達式
    
    Args:
        expression: 數學表達式字符串
    
    Returns:
        {"success": bool, "result": str, "error": str}
    """
    try:
        # 預處理表達式
        expr = _preprocess_expression(expression)
        
        # 驗證表達式安全性
        if not _is_safe_expression(expr):
            return {
                "success": False,
                "result": "",
                "error": "表達式包含不允許的字符或函數"
            }
        
        # 執行計算
        result = eval(expr, {"__builtins__": {}}, SAFE_MATH_FUNCTIONS)
        
        # 格式化結果
        if isinstance(result, float):
            # 如果是整數結果，去掉小數點
            if result == int(result):
                result = int(result)
            else:
                # 保留合理的小數位數
                result = round(result, 10)
        
        return {
            "success": True,
            "result": str(result),
            "error": ""
        }
        
    except ZeroDivisionError:
        return {"success": False, "result": "", "error": "除以零錯誤"}
    except ValueError as e:
        return {"success": False, "result": "", "error": f"數值錯誤: {str(e)}"}
    except SyntaxError:
        return {"success": False, "result": "", "error": "表達式語法錯誤"}
    except Exception as e:
        return {"success": False, "result": "", "error": f"計算錯誤: {str(e)}"}


def _preprocess_expression(expression: str) -> str:
    """預處理表達式"""
    expr = expression.strip()
    
    # 替換常見符號
    replacements = {
        '×': '*',
        '÷': '/',
        '：': '/',
        '^': '**',
        '（': '(',
        '）': ')',
        '％': '%',
        '．': '.',
    }
    
    for old, new in replacements.items():
        expr = expr.replace(old, new)
    
    # 移除空格
    expr = expr.replace(' ', '')
    
    return expr


def _is_safe_expression(expression: str) -> bool:
    """檢查表達式是否安全"""
    # 只允許數字、運算符和白名單函數
    allowed_pattern = r'^[\d\.\+\-\*\/\%\(\)\,\s' + ''.join(SAFE_MATH_FUNCTIONS.keys()) + r']+$'
    
    # 簡化檢查：只允許基本字符
    safe_chars = set('0123456789.+-*/%()[], ')
    safe_words = set(SAFE_MATH_FUNCTIONS.keys())
    
    # 移除已知安全的函數名
    test_expr = expression
    for word in safe_words:
        test_expr = test_expr.replace(word, '')
    
    # 檢查剩餘字符
    for char in test_expr:
        if char not in safe_chars:
            return False
    
    # 禁止危險模式
    dangerous_patterns = ['__', 'import', 'exec', 'eval', 'open', 'file', 'os.', 'sys.']
    for pattern in dangerous_patterns:
        if pattern in expression.lower():
            return False
    
    return True


def open_system_calculator() -> dict:
    """打開系統計算器"""
    try:
        # Windows
        subprocess.Popen(['calc.exe'])
        return {"success": True, "message": "計算器已打開"}
    except FileNotFoundError:
        try:
            # Linux (gnome-calculator)
            subprocess.Popen(['gnome-calculator'])
            return {"success": True, "message": "計算器已打開"}
        except FileNotFoundError:
            try:
                # macOS
                subprocess.Popen(['open', '-a', 'Calculator'])
                return {"success": True, "message": "計算器已打開"}
            except Exception as e:
                return {"success": False, "message": f"無法打開計算器: {str(e)}"}


# ===== 測試 =====
if __name__ == "__main__":
    test_expressions = [
        "2+3*4",
        "10/2-1",
        "sqrt(16)",
        "sin(0)",
        "2**10",
        "pi * 2",
        "(1+2)*(3+4)",
        "100%7",
    ]
    
    print("計算器測試:")
    for expr in test_expressions:
        result = calculate_expression(expr)
        if result["success"]:
            print(f"  {expr} = {result['result']}")
        else:
            print(f"  {expr} => 錯誤: {result['error']}")
