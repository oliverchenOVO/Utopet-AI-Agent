from PyQt5 import QtCore, QtGui, QtWidgets
from PIL import Image, ImageGrab
import io

class OcrResultWindow(QtWidgets.QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("📄 截圖文字辨識結果")
        self.resize(700, 550)
        # 讓視窗總是在最上層，避免被 Godot 擋住
        self.setWindowFlags(self.windowFlags() | QtCore.Qt.WindowStaysOnTopHint)

        # --- UI 元件 ---
        self.search_box = QtWidgets.QLineEdit(self)
        self.search_box.setPlaceholderText("搜尋內容...")
        
        self.text_edit = QtWidgets.QPlainTextEdit(self)
        self.text_edit.setReadOnly(False)
        self.text_edit.setLineWrapMode(QtWidgets.QPlainTextEdit.WidgetWidth)

        self.status = QtWidgets.QLabel("請選擇圖片或貼上...")
        status_bar = QtWidgets.QStatusBar(self)
        status_bar.addPermanentWidget(self.status)

        # --- 按鈕區 ---
        # 新增功能按鈕
        btn_open_img = QtWidgets.QPushButton("📂 開啟圖片")
        btn_paste_img = QtWidgets.QPushButton("📋 剪貼簿圖片辨識")
        
        # 原有按鈕
        btn_copy = QtWidgets.QPushButton("複製")
        btn_save = QtWidgets.QPushButton("儲存")
        
        # 樣式優化 (可選)
        btn_paste_img.setStyleSheet("font-weight: bold; color: #0055aa;")

        # --- 佈局 ---
        top_layout = QtWidgets.QHBoxLayout()
        top_layout.addWidget(btn_open_img)
        top_layout.addWidget(btn_paste_img)
        top_layout.addWidget(self.search_box)
        top_layout.addWidget(btn_copy)
        top_layout.addWidget(btn_save)

        main_layout = QtWidgets.QVBoxLayout(self)
        main_layout.addLayout(top_layout)
        main_layout.addWidget(self.text_edit)
        main_layout.addWidget(status_bar)

        # --- 事件連接 ---
        btn_open_img.clicked.connect(self.on_open_image)
        btn_paste_img.clicked.connect(self.on_paste_image)
        
        btn_copy.clicked.connect(self.copy_all)
        btn_save.clicked.connect(self.save_text)
        
        self.search_box.returnPressed.connect(self.find_next)
        
        self.text_edit.textChanged.connect(self._update_status)

        # 這是用來存外部傳進來的 OCR 函數
        self.ocr_callback_func = None

    def set_ocr_callback(self, func):
        """由 main.py 呼叫，把 OCR 的功能傳進來給視窗用"""
        self.ocr_callback_func = func

    def on_open_image(self):
        """開啟檔案對話框選擇圖片"""
        path, _ = QtWidgets.QFileDialog.getOpenFileName(
            self, "選擇圖片", "", "Images (*.png *.jpg *.jpeg *.bmp *.webp)"
        )
        if path:
            self.status.setText("正在辨識中...")
            QtWidgets.QApplication.processEvents() # 強制刷新 UI 顯示文字
            try:
                img = Image.open(path)
                self._run_ocr(img)
            except Exception as e:
                self.text_edit.setPlainText(f"開啟圖片失敗：{e}")

    def on_paste_image(self):
        """從剪貼簿獲取圖片"""
        try:
            img = ImageGrab.grabclipboard()
            if isinstance(img, Image.Image):
                self.status.setText("正在辨識剪貼簿圖片...")
                QtWidgets.QApplication.processEvents()
                self._run_ocr(img)
            else:
                self.status.setText("剪貼簿裡沒有圖片！")
                QtWidgets.QMessageBox.warning(self, "提示", "剪貼簿中沒有圖片。")
        except Exception as e:
            self.text_edit.setPlainText(f"讀取剪貼簿失敗：{e}")

    def _run_ocr(self, img):
        """執行 OCR (呼叫 main.py 傳進來的函數)"""
        if self.ocr_callback_func:
            try:
                text = self.ocr_callback_func(img)
                self.set_text(text)
                self.status.setText("辨識完成")
            except Exception as e:
                self.text_edit.setPlainText(f"OCR 辨識錯誤：{e}")
        else:
            self.text_edit.setPlainText("錯誤：OCR 功能未連接 (Callback not set)")

    def set_text(self, text: str):
        self.text_edit.setPlainText(text or "")
        self.text_edit.moveCursor(QtGui.QTextCursor.Start)
        self._update_status()

    def copy_all(self):
        self.text_edit.selectAll()
        self.text_edit.copy()
        self.status.setText("已複製")

    def save_text(self):
        path, _ = QtWidgets.QFileDialog.getSaveFileName(self, "另存文字", "ocr_result.txt", "Text (*.txt)")
        if path:
            with open(path, "w", encoding="utf-8") as f:
                f.write(self.text_edit.toPlainText())
            self.status.setText(f"已儲存：{path}")

    def find_next(self):
        # 簡單的搜尋功能
        key = self.search_box.text()
        if not key: return
        if not self.text_edit.find(key):
            # 找不到就回到開頭再找一次
            self.text_edit.moveCursor(QtGui.QTextCursor.Start)
            self.text_edit.find(key)

    def _update_status(self):
        text = self.text_edit.toPlainText()
        self.status.setText(f"字數：{len(text)}")