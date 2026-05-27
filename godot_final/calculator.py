# -*- coding: utf-8 -*-
"""
Doro Desktop Pet - 計算器助手模組
負責計算器功能的實現
"""
import subprocess
import time
import re
from PyQt5 import QtWidgets
from config import PetConfig

try:
    import pyautogui
    pyautogui.FAILSAFE = False
    PYAUTOGUI_AVAILABLE = True
except ImportError:
    PYAUTOGUI_AVAILABLE = False

class CalculatorHelper:
    """計算器助手類"""

    def __init__(self, pet_instance=None):
        self.pet = pet_instance
        self.config = PetConfig()
    
    def is_available(self):
        """檢查計算器功能是否可用"""
        return PYAUTOGUI_AVAILABLE
    
    def show_dependency_warning(self, parent=None):
        """顯示依賴缺失警告"""
        QtWidgets.QMessageBox.warning(
            parent, "缺少依賴", 
            "需要安裝 pyautogui 庫才能使用計算器功能！\n\n請運行：pip install pyautogui"
        )
    
    def open_calculator_dialog(self, parent=None):
        """打開計算器輸入對話框"""
        if not self.is_available():
            self.show_dependency_warning(parent)
            return None
        
        text, ok = QtWidgets.QInputDialog.getText(
            parent, "計算器助手", 
            "請輸入要計算的算式：\n例如：2+3*4, 10/2-1, sqrt(16), sin(30) 等\n\n算式："
        )
        
        if self.pet:
            self.pet.hide_thinking()
        
        if ok and text.strip():
            return text.strip()
        return None
    
    def calculate_with_system_calculator(self, expression):
        """使用系統計算器進行計算"""
        try:
            # 通知開始計算
            if self.pet:
                self.pet.ai_speak(
                    self.config.calculator_messages["start"].format(expression), 
                    "think"
                )
            
            # 啟動Windows計算器
            if self.pet:
                self.pet.ai_speak(
                    self.config.calculator_messages["launching"], 
                    "talking"
                )
            
            subprocess.Popen(['calc.exe'])
            time.sleep(2)
            
            # 清空計算器
            self._clear_calculator()
            
            # 輸入算式
            self._input_expression(expression)
            
            # 按等號獲得結果
            time.sleep(0.5)
            pyautogui.press('enter')
            
            # 通知完成
            if self.pet:
                self.pet.ai_speak(
                    self.config.calculator_messages["complete"], 
                    "happy"
                )
            
        except Exception as e:
            error_msg = self.config.calculator_messages["error"].format(str(e))
            if self.pet:
                self.pet.ai_speak(error_msg, "sad")
    
    def _clear_calculator(self):
        """清空計算器"""
        pyautogui.press('escape')
        time.sleep(0.1)
        pyautogui.press('delete')
        time.sleep(0.5)
    
    def _input_expression(self, expression):
        """輸入算式到計算器"""
        # 預處理算式
        expression = self._preprocess_expression(expression)
        
        # 處理特殊函數
        if self._handle_special_functions(expression):
            return
        
        # 逐字符輸入
        self._input_characters(expression)
    
    def _preprocess_expression(self, expression):
        """預處理算式，替換常見符號"""
        replacements = {
            '×': '*',
            '÷': '/',
            '**': '^'
        }
        
        for old, new in replacements.items():
            expression = expression.replace(old, new)
        
        return expression
    
    def _handle_special_functions(self, expression):
        """處理特殊數學函數"""
        # 處理平方根
        if 'sqrt(' in expression:
            match = re.search(r'sqrt\(([^)]+)\)', expression)
            if match:
                number = match.group(1)
                pyautogui.typewrite(number)
                time.sleep(0.2)
                pyautogui.hotkey('ctrl', 'shift', '2')
                return True
        
        # 處理三角函數
        if any(func in expression for func in ['sin(', 'cos(', 'tan(']):
            # 切換到科學計算器模式
            pyautogui.hotkey('alt', '2')
            time.sleep(0.5)
        
        return False
    
    def _input_characters(self, expression):
        """逐字符輸入算式"""
        i = 0
        while i < len(expression):
            char = expression[i]
            
            if char.isdigit():
                pyautogui.press(char)
            elif char in ['+', '-', '*', '/']:
                pyautogui.press(char)
            elif char == '.':
                pyautogui.press('decimal')
            elif char in ['(', ')']:
                pyautogui.press(char)
            elif char == '^':
                pyautogui.hotkey('ctrl', 'shift', '6')
            elif char in 'sincot':
                i = self._handle_trig_functions(expression, i)
            elif char == ' ':
                pass  # 忽略空格
            else:
                pyautogui.typewrite(char)
            
            time.sleep(0.1)
            i += 1
    
    def _handle_trig_functions(self, expression, index):
        """處理三角函數輸入"""
        if expression[index:index+4] == 'sin(':
            pyautogui.press('s')
            return index + 3
        elif expression[index:index+4] == 'cos(':
            pyautogui.press('o')
            return index + 3
        elif expression[index:index+4] == 'tan(':
            pyautogui.press('t')
            return index + 3
        return index