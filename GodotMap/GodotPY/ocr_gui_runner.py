import sys
from PyQt5 import QtWidgets
from ocr_helper import OCRHelper
from ocr_result_window import OcrResultWindow

def main():
    # 1. 初始化 PyQt (必須在主執行緒)
    app = QtWidgets.QApplication(sys.argv)
    
    # 2. 初始化 OCR 引擎
    print("[GUI] 正在載入 OCR 引擎...")
    try:
        ocr_helper = OCRHelper(use_angle_cls=True)
        callback = ocr_helper.extract_text_from_pil
    except Exception as e:
        print(f"[GUI] OCR 引擎載入失敗: {e}")
        callback = None

    # 3. 建立並顯示視窗
    window = OcrResultWindow()
    window.setWindowTitle("OCR 文字辨識 (獨立視窗)")
    
    if callback:
        window.set_ocr_callback(callback)
    else:
        window.text_edit.setPlainText("錯誤：OCR 引擎無法載入，請檢查 console。")

    window.show()
    window.raise_()        # 嘗試將視窗推到最上層
    window.activateWindow()
    
    # 4. 進入主迴圈
    sys.exit(app.exec_())

if __name__ == "__main__":
    main()