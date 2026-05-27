# ocr_helper.py
import numpy as np
from PIL import Image

class OCRHelper:
    """
    統一的 OCR 介面：
    - 優先使用 PaddleOCR（若可用）
    - 否則自動退回 RapidOCR（onnxruntime）
    """
    def __init__(self, lang="ch", use_angle_cls=True):
        self.backend = None
        self.lang = lang
        self.use_angle_cls = use_angle_cls
        self._init_backend()

    def recognize_image(self, image):
        """識別圖像中的文字"""
        try:
            # 如果您有實際的 OCR 實現，請在這裡替換
            # 這是一個基本的占位符實現
            return "OCR 功能需要配置具體的實現"
        except Exception as e:
            print(f"OCR 識別錯誤: {e}")
            return f"OCR 錯誤: {str(e)}"

    def _init_backend(self):
        try:
            from paddleocr import PaddleOCR
            self.backend = ("paddle", PaddleOCR(lang=self.lang, use_angle_cls=self.use_angle_cls))
            return
        except Exception:
            pass
        try:
            from rapidocr_onnxruntime import RapidOCR
            self.backend = ("rapid", RapidOCR())
            return
        except Exception as e:
            raise RuntimeError(f"無可用 OCR 後端：{e}")

    def extract_text_from_pil(self, pil_img: Image.Image) -> str:
        if self.backend[0] == "paddle":
            PaddleOCR = self.backend[1]
            arr = np.array(pil_img)
            result = PaddleOCR.ocr(arr, cls=True)
            lines = []
            for page in result:
                for line in page:
                    txt = line[1][0]
                    if txt:
                        lines.append(txt)
            return "\n".join(lines).strip()
        else:
            Rapid = self.backend[1]
            arr = np.array(pil_img)
            result, _ = Rapid(arr)  # [ [box, text, score], ... ]
            lines = [item[1] for item in (result or []) if item and len(item) >= 2]
            return "\n".join(lines).strip()

    def extract_text(self, image_path: str) -> str:
        if self.backend[0] == "paddle":
            PaddleOCR = self.backend[1]
            result = PaddleOCR.ocr(image_path, cls=True)
            lines = []
            for page in result:
                for line in page:
                    txt = line[1][0]
                    if txt:
                        lines.append(txt)
            return "\n".join(lines).strip()
        else:
            Rapid = self.backend[1]
            result, _ = Rapid(image_path)
            lines = [item[1] for item in (result or []) if item and len(item) >= 2]
            return "\n".join(lines).strip()