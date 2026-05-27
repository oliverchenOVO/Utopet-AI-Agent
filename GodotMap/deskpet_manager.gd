# deskpet_manager_enhanced.gd - 增強版桌寵管理器 v2.1
# 修復摘要對話框，添加計算器功能
extends Node

# ===== 信號 =====
signal deskpet_opened(agent_data: Dictionary)
signal deskpet_closed()

# ===== UI組件 =====
var canvas_layer: CanvasLayer = null
var panel_container: PanelContainer = null
var current_agent_ref: Node = null
var context_menu: PopupMenu = null
var pet_sprite: AnimatedSprite2D = null

# ===== Python API客戶端 =====
var python_client: Node = null

# ===== 拖曳狀態 =====
var _dragging = false
var _drag_offset = Vector2.ZERO

# ===== 活動對話框 =====
var _active_dialog: Control = null

# ===== 右鍵選單項目ID =====
enum MenuID {
	PROPERTY_PANEL = 0,
	SEPARATOR_1 = 1,
	OCR_CAPTURE = 10,
	SPEECH_INPUT = 11,
	AI_CHAT = 12,
	SEPARATOR_2 = 20,
	SUMMARIZE_NEWS = 21,
	SUMMARIZE_ARTICLE = 22,
	SEPARATOR_3 = 30,
	CALCULATOR = 31,
	OPEN_SYSTEM_CALC = 32,
	SEPARATOR_4 = 40,
	CHECK_SERVER = 50,
	SEPARATOR_5 = 60,
	CLOSE_PET = 99
}

func _ready() -> void:
	print("🐾 增強版桌寵管理器 v2.1 初始化...")
	_setup_python_client()

func _setup_python_client() -> void:
	"""設置Python API客戶端"""
	var client_script = load("res://python_api_client.gd")
	if client_script:
		python_client = client_script.new()
		python_client.name = "PythonAPIClient"
		add_child(python_client)
		
		# 連接信號
		python_client.ocr_window_opened.connect(_on_ocr_opened)
		python_client.speech_result_received.connect(_on_speech_result)
		python_client.speech_error.connect(_on_speech_error)
		python_client.chat_response_received.connect(_on_chat_response)
		python_client.summary_received.connect(_on_summary_received)
		python_client.calculate_result_received.connect(_on_calculate_result)
		python_client.calculator_opened.connect(_on_calculator_opened)
		python_client.api_error.connect(_on_api_error)
		
		print("🐍 Python API客戶端已連接")
	else:
		print("⚠️ 無法加載Python API客戶端，部分功能可能不可用")

# ===== 主要功能 =====

func open_deskpet(agent: Node) -> void:
	"""打開桌寵面板"""
	print("🐾 開始打開桌寵...")
	
	if panel_container and is_instance_valid(panel_container):
		print("🔄 替換現有桌寵...")
		close_deskpet()
	
	current_agent_ref = agent
	_create_deskpet_panel(agent)
	
	var agent_name = agent.agent_name if "agent_name" in agent else "Unknown"
	print("🐾 桌寵已打開: %s" % agent_name)
	
	var agent_data = _get_agent_data(agent)
	deskpet_opened.emit(agent_data)

func close_deskpet() -> void:
	"""關閉桌寵面板"""
	if canvas_layer and is_instance_valid(canvas_layer):
		canvas_layer.queue_free()
		canvas_layer = null
		panel_container = null
		current_agent_ref = null
		print("🐾 桌寵已關閉")
		deskpet_closed.emit()

func is_deskpet_open() -> bool:
	return panel_container != null and is_instance_valid(panel_container)

# ===== UI創建 =====

func _create_deskpet_panel(agent: Node) -> void:
	"""創建桌寵UI面板"""
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100
	get_tree().root.add_child(canvas_layer)
	
	panel_container = PanelContainer.new()
	panel_container.custom_minimum_size = Vector2(110, 130)
	panel_container.size = Vector2(110, 130)
	
	var viewport_size = get_viewport().get_visible_rect().size
	panel_container.position = Vector2(viewport_size.x - 130, viewport_size.y - 150)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel_container.add_theme_stylebox_override("panel", style)
	
	canvas_layer.add_child(panel_container)
	_setup_panel_content(agent)

func _setup_panel_content(agent: Node) -> void:
	"""設置面板內容"""
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_container.add_child(main_vbox)
	
	# 頂部區域
	var top_hbox = HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(top_hbox)
	
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(24, 24)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(_on_close_button_pressed)
	close_btn.tooltip_text = "關閉桌寵 (F9)"
	top_hbox.add_child(close_btn)
	
	# 精靈容器
	var sprite_container = CenterContainer.new()
	sprite_container.custom_minimum_size = Vector2(100, 60)
	main_vbox.add_child(sprite_container)
	
	_copy_agent_sprite(agent, sprite_container)
	
	# 名字標籤
	var name_label = Label.new()
	name_label.text = agent.agent_name if "agent_name" in agent else "Agent"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	main_vbox.add_child(name_label)
	
	_setup_context_menu()
	panel_container.gui_input.connect(_on_panel_input)

func _copy_agent_sprite(agent: Node, container: Control) -> void:
	"""複製Agent的精靈"""
	var original_sprite: AnimatedSprite2D = null
	for child in agent.get_children():
		if child is AnimatedSprite2D:
			original_sprite = child
			break
	
	if original_sprite and original_sprite.sprite_frames:
		var pivot = Control.new()
		container.add_child(pivot)
		
		pet_sprite = AnimatedSprite2D.new()
		pet_sprite.sprite_frames = original_sprite.sprite_frames
		pet_sprite.animation = original_sprite.animation
		pet_sprite.scale = Vector2(1.8, 1.8)
		pet_sprite.play()
		pivot.add_child(pet_sprite)
	else:
		var placeholder = ColorRect.new()
		placeholder.custom_minimum_size = Vector2(32, 32)
		placeholder.color = Color.CORAL
		container.add_child(placeholder)

# ===== 增強版右鍵選單 =====

func _setup_context_menu() -> void:
	"""設置增強版右鍵選單"""
	context_menu = PopupMenu.new()
	
	context_menu.add_item("📋 屬性面板", MenuID.PROPERTY_PANEL)
	context_menu.add_separator("", MenuID.SEPARATOR_1)
	
	context_menu.add_item("📷 OCR文字識別", MenuID.OCR_CAPTURE)
	context_menu.add_item("🎤 語音輸入", MenuID.SPEECH_INPUT)
	context_menu.add_item("💬 AI對話", MenuID.AI_CHAT)
	context_menu.add_separator("", MenuID.SEPARATOR_2)
	
	context_menu.add_item("📰 新聞摘要", MenuID.SUMMARIZE_NEWS)
	context_menu.add_item("📄 文章摘要", MenuID.SUMMARIZE_ARTICLE)
	context_menu.add_separator("", MenuID.SEPARATOR_3)
	
	context_menu.add_item("🔢 快速計算", MenuID.CALCULATOR)
	context_menu.add_item("🖩 打開計算器", MenuID.OPEN_SYSTEM_CALC)
	context_menu.add_separator("", MenuID.SEPARATOR_4)
	
	context_menu.add_item("🔍 檢查服務器", MenuID.CHECK_SERVER)
	context_menu.add_separator("", MenuID.SEPARATOR_5)
	
	context_menu.add_item("❌ 關閉桌寵", MenuID.CLOSE_PET)
	
	context_menu.id_pressed.connect(_on_context_menu_selected)
	canvas_layer.add_child(context_menu)

func _on_panel_input(event: InputEvent) -> void:
	"""處理面板輸入"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			context_menu.position = Vector2i(get_viewport().get_mouse_position())
			context_menu.popup()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_offset = event.position
			else:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		panel_container.position += event.relative

func _on_context_menu_selected(id: int) -> void:
	"""處理選單選擇"""
	match id:
		MenuID.PROPERTY_PANEL:
			_show_property_panel()
		MenuID.OCR_CAPTURE:
			_open_ocr()
		MenuID.SPEECH_INPUT:
			_start_speech()
		MenuID.AI_CHAT:
			_open_ai_chat()
		MenuID.SUMMARIZE_NEWS:
			_open_summarize_dialog("news")
		MenuID.SUMMARIZE_ARTICLE:
			_open_summarize_dialog("article")
		MenuID.CALCULATOR:
			_open_calculator_dialog()
		MenuID.OPEN_SYSTEM_CALC:
			_open_system_calculator()
		MenuID.CHECK_SERVER:
			_check_python_server()
		MenuID.CLOSE_PET:
			close_deskpet()

func _on_close_button_pressed() -> void:
	close_deskpet()

# ===== Python功能實現 =====

func _open_ocr() -> void:
	if python_client:
		_show_toast("正在打開OCR視窗...")
		python_client.open_ocr_window()
	else:
		_show_error_dialog("Python服務未連接", "請確保Python API服務器正在運行")

func _start_speech() -> void:
	if python_client:
		_show_toast("🎤 正在聆聽...")
		python_client.start_speech_recognition()
	else:
		_show_error_dialog("Python服務未連接", "請確保Python API服務器正在運行")

func _open_ai_chat() -> void:
	"""打開AI對話輸入框 - 超緊湊版"""
	var viewport_size = get_viewport().get_visible_rect().size
	var dialog_width = min(180, viewport_size.x - 10)
	var dialog_height = min(90, viewport_size.y - 10)
	
	var dialog_bg = ColorRect.new()
	dialog_bg.color = Color(0, 0, 0, 0.5)
	dialog_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(dialog_bg)
	
	var dialog = PanelContainer.new()
	dialog.custom_minimum_size = Vector2(dialog_width, dialog_height)
	dialog.size = Vector2(dialog_width, dialog_height)
	dialog.position = Vector2(
		(viewport_size.x - dialog_width) / 2,
		(viewport_size.y - dialog_height) / 2
	)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	dialog.add_theme_stylebox_override("panel", style)
	canvas_layer.add_child(dialog)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)
	
	# 標題行
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var title_label = Label.new()
	title_label.text = "💬 AI"
	title_label.add_theme_font_size_override("font_size", 9)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	
	var close_x = Button.new()
	close_x.text = "✕"
	close_x.custom_minimum_size = Vector2(14, 14)
	close_x.add_theme_font_size_override("font_size", 8)
	header.add_child(close_x)
	
	# 輸入框
	var line_edit = LineEdit.new()
	line_edit.placeholder_text = "輸入問題..."
	line_edit.custom_minimum_size = Vector2(0, 20)
	line_edit.add_theme_font_size_override("font_size", 9)
	vbox.add_child(line_edit)
	
	# 按鈕
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_container)
	
	var send_btn = Button.new()
	send_btn.text = "發送"
	send_btn.custom_minimum_size = Vector2(40, 16)
	send_btn.add_theme_font_size_override("font_size", 8)
	btn_container.add_child(send_btn)
	
	var close_dialog = func():
		dialog_bg.queue_free()
		dialog.queue_free()
		_active_dialog = null
	
	send_btn.pressed.connect(func():
		var text = line_edit.text.strip_edges()
		if text != "" and python_client:
			_show_toast("AI思考中...")
			python_client.send_chat_message(text)
			close_dialog.call()
	)
	
	line_edit.text_submitted.connect(func(text: String):
		if text.strip_edges() != "" and python_client:
			_show_toast("AI思考中...")
			python_client.send_chat_message(text.strip_edges())
			close_dialog.call()
	)
	
	close_x.pressed.connect(close_dialog)
	dialog_bg.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			close_dialog.call()
	)
	
	dialog.set_meta("close_func", close_dialog)
	dialog.set_meta("dialog_bg", dialog_bg)
	_active_dialog = dialog
	line_edit.grab_focus()

func _open_summarize_dialog(type: String) -> void:
	"""打開摘要輸入對話框 - 超緊湊版"""
	var title_text = "📰 新聞" if type == "news" else "📄 文章"
	
	# 獲取視口大小，計算合適的對話框尺寸（為小視口優化）
	var viewport_size = get_viewport().get_visible_rect().size
	var dialog_width = min(200, viewport_size.x - 10)
	var dialog_height = min(180, viewport_size.y - 10)
	
	# 創建半透明背景
	var dialog_bg = ColorRect.new()
	dialog_bg.color = Color(0, 0, 0, 0.5)
	dialog_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(dialog_bg)
	
	var dialog = PanelContainer.new()
	dialog.custom_minimum_size = Vector2(dialog_width, dialog_height)
	dialog.size = Vector2(dialog_width, dialog_height)
	dialog.position = Vector2(
		(viewport_size.x - dialog_width) / 2,
		(viewport_size.y - dialog_height) / 2
	)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	dialog.add_theme_stylebox_override("panel", style)
	canvas_layer.add_child(dialog)
	
	# 外層邊距（更小）
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)
	
	# 標題行（帶關閉按鈕）
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var title_label = Label.new()
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	
	var close_x = Button.new()
	close_x.text = "✕"
	close_x.custom_minimum_size = Vector2(16, 16)
	close_x.add_theme_font_size_override("font_size", 8)
	header.add_child(close_x)
	
	# 標題輸入（單行）
	var title_edit = LineEdit.new()
	title_edit.placeholder_text = "標題(可選)"
	title_edit.custom_minimum_size = Vector2(0, 18)
	title_edit.add_theme_font_size_override("font_size", 9)
	vbox.add_child(title_edit)
	
	# 內容輸入
	var content_edit = TextEdit.new()
	content_edit.placeholder_text = "貼上內容..."
	content_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_edit.custom_minimum_size = Vector2(0, 60)
	content_edit.add_theme_font_size_override("font_size", 9)
	vbox.add_child(content_edit)
	
	# 按鈕區域
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_container)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size = Vector2(40, 18)
	cancel_btn.add_theme_font_size_override("font_size", 9)
	btn_container.add_child(cancel_btn)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(4, 0)
	btn_container.add_child(spacer)
	
	var submit_btn = Button.new()
	submit_btn.text = "生成"
	submit_btn.custom_minimum_size = Vector2(40, 18)
	submit_btn.add_theme_font_size_override("font_size", 9)
	btn_container.add_child(submit_btn)
	
	# 關閉函數
	var close_dialog = func():
		dialog_bg.queue_free()
		dialog.queue_free()
		_active_dialog = null
	
	# 連接事件
	submit_btn.pressed.connect(func():
		var title = title_edit.text.strip_edges()
		var content = content_edit.text.strip_edges()
		if content != "" and python_client:
			_show_toast("生成中...")
			if type == "news":
				python_client.summarize_news(title, content)
			else:
				python_client.summarize_article(title, content)
			close_dialog.call()
		elif content == "":
			_show_toast("請輸入內容")
	)
	
	cancel_btn.pressed.connect(close_dialog)
	close_x.pressed.connect(close_dialog)
	dialog_bg.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			close_dialog.call()
	)
	
	# 存儲對話框引用以便ESC關閉
	dialog.set_meta("close_func", close_dialog)
	dialog.set_meta("dialog_bg", dialog_bg)
	_active_dialog = dialog

func _open_calculator_dialog() -> void:
	"""打開快速計算對話框 - 超緊湊版"""
	var viewport_size = get_viewport().get_visible_rect().size
	var dialog_width = min(180, viewport_size.x - 10)
	var dialog_height = min(100, viewport_size.y - 10)
	
	# 背景遮罩
	var dialog_bg = ColorRect.new()
	dialog_bg.color = Color(0, 0, 0, 0.5)
	dialog_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(dialog_bg)
	
	var dialog = PanelContainer.new()
	dialog.custom_minimum_size = Vector2(dialog_width, dialog_height)
	dialog.size = Vector2(dialog_width, dialog_height)
	dialog.position = Vector2(
		(viewport_size.x - dialog_width) / 2,
		(viewport_size.y - dialog_height) / 2
	)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	dialog.add_theme_stylebox_override("panel", style)
	canvas_layer.add_child(dialog)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)
	
	# 標題行
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var title_label = Label.new()
	title_label.text = "🔢 計算"
	title_label.add_theme_font_size_override("font_size", 9)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	
	var close_x = Button.new()
	close_x.text = "✕"
	close_x.custom_minimum_size = Vector2(14, 14)
	close_x.add_theme_font_size_override("font_size", 8)
	header.add_child(close_x)
	
	# 輸入框
	var expr_edit = LineEdit.new()
	expr_edit.placeholder_text = "2+3*4"
	expr_edit.custom_minimum_size = Vector2(0, 18)
	expr_edit.add_theme_font_size_override("font_size", 9)
	vbox.add_child(expr_edit)
	
	# 結果
	var result_label = Label.new()
	result_label.text = "= "
	result_label.add_theme_font_size_override("font_size", 10)
	result_label.add_theme_color_override("font_color", Color.YELLOW)
	vbox.add_child(result_label)
	
	# 按鈕
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_container)
	
	var calc_btn = Button.new()
	calc_btn.text = "計算"
	calc_btn.custom_minimum_size = Vector2(40, 16)
	calc_btn.add_theme_font_size_override("font_size", 8)
	btn_container.add_child(calc_btn)
	
	# 關閉函數
	var close_dialog = func():
		var on_result_ref = dialog.get_meta("on_result", Callable())
		if python_client and on_result_ref.is_valid():
			if python_client.calculate_result_received.is_connected(on_result_ref):
				python_client.calculate_result_received.disconnect(on_result_ref)
		dialog_bg.queue_free()
		dialog.queue_free()
		_active_dialog = null
	
	# 臨時結果回調
	var on_result = func(result: String):
		result_label.text = "= " + result
	
	# 保存回調引用
	dialog.set_meta("on_result", on_result)
	
	if python_client:
		python_client.calculate_result_received.connect(on_result)
	
	calc_btn.pressed.connect(func():
		var expr = expr_edit.text.strip_edges()
		if expr != "" and python_client:
			python_client.calculate_expression(expr)
	)
	
	expr_edit.text_submitted.connect(func(text: String):
		if text.strip_edges() != "" and python_client:
			python_client.calculate_expression(text.strip_edges())
	)
	
	close_x.pressed.connect(close_dialog)
	dialog_bg.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			close_dialog.call()
	)
	
	dialog.set_meta("close_func", close_dialog)
	dialog.set_meta("dialog_bg", dialog_bg)
	_active_dialog = dialog
	expr_edit.grab_focus()

func _on_calc_temp_result(result: String) -> void:
	# 佔位函數
	pass

func _open_system_calculator() -> void:
	"""打開系統計算器"""
	if python_client:
		python_client.open_system_calculator()
	else:
		_show_error_dialog("Python服務未連接", "請確保Python API服務器正在運行")

func _check_python_server() -> void:
	if python_client:
		_show_toast("正在檢查服務器...")
		python_client.check_server_health(func(success: bool, error: String):
			if success:
				_show_result_dialog("✅ 服務器狀態", "Python API服務器運行正常！\n\n服務器地址：http://127.0.0.1:8000\n\n可用功能：\n• AI聊天\n• 語音識別\n• OCR文字識別\n• 新聞/文章摘要\n• 快速計算")
			else:
				_show_error_dialog("❌ 服務器未響應", "請確保已啟動Python API服務器：\n\ncd GodotPY\npython main.py")
		)
	else:
		_show_error_dialog("Python客戶端未初始化", "請重新載入場景")

# ===== Python API回調 =====

func _on_ocr_opened() -> void:
	_show_toast("OCR視窗已打開")

func _on_speech_result(text: String) -> void:
	if text != "":
		_show_result_dialog("🎤 語音識別結果", text)
	else:
		_show_toast("未識別到語音")

func _on_speech_error(error: String) -> void:
	_show_error_dialog("語音識別失敗", error)

func _on_chat_response(response: String) -> void:
	_show_result_dialog("💬 AI回應", response)

func _on_summary_received(summary: String, points: Array) -> void:
	var result_text = summary
	if points.size() > 0:
		result_text += "\n\n📌 要點：\n"
		for point in points:
			result_text += "• " + str(point) + "\n"
	_show_result_dialog("📝 摘要結果", result_text)

func _on_calculate_result(result: String) -> void:
	# 結果已在對話框中顯示，這裡可以額外處理
	pass

func _on_calculator_opened() -> void:
	_show_toast("系統計算器已打開")

func _on_api_error(endpoint: String, error: String) -> void:
	_show_error_dialog("API錯誤 [%s]" % endpoint, error)

# ===== 對話框工具 =====

func _show_result_dialog(title: String, content: String) -> void:
	"""顯示結果對話框 - 超緊湊版"""
	var viewport_size = get_viewport().get_visible_rect().size
	var dialog_width = min(200, viewport_size.x - 10)
	var dialog_height = min(180, viewport_size.y - 10)
	
	var dialog_bg = ColorRect.new()
	dialog_bg.color = Color(0, 0, 0, 0.5)
	dialog_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(dialog_bg)
	
	var dialog = PanelContainer.new()
	dialog.custom_minimum_size = Vector2(dialog_width, dialog_height)
	dialog.size = Vector2(dialog_width, dialog_height)
	dialog.position = Vector2(
		(viewport_size.x - dialog_width) / 2,
		(viewport_size.y - dialog_height) / 2
	)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	dialog.add_theme_stylebox_override("panel", style)
	canvas_layer.add_child(dialog)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)
	
	# 標題行
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 9)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	
	var close_x = Button.new()
	close_x.text = "✕"
	close_x.custom_minimum_size = Vector2(14, 14)
	close_x.add_theme_font_size_override("font_size", 8)
	header.add_child(close_x)
	
	# 內容滾動區
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var content_label = Label.new()
	content_label.text = content
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_label.custom_minimum_size = Vector2(dialog_width - 15, 0)
	content_label.add_theme_font_size_override("font_size", 8)
	scroll.add_child(content_label)
	
	# 關閉按鈕
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_container)
	
	var close_btn = Button.new()
	close_btn.text = "關閉"
	close_btn.custom_minimum_size = Vector2(40, 16)
	close_btn.add_theme_font_size_override("font_size", 8)
	btn_container.add_child(close_btn)
	
	var close_dialog = func():
		dialog_bg.queue_free()
		dialog.queue_free()
		_active_dialog = null
	
	close_btn.pressed.connect(close_dialog)
	close_x.pressed.connect(close_dialog)
	dialog_bg.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			close_dialog.call()
	)
	
	dialog.set_meta("close_func", close_dialog)
	dialog.set_meta("dialog_bg", dialog_bg)
	_active_dialog = dialog

func _show_error_dialog(title: String, message: String) -> void:
	"""顯示錯誤對話框 - 超緊湊版"""
	var viewport_size = get_viewport().get_visible_rect().size
	var dialog_width = min(180, viewport_size.x - 10)
	var dialog_height = min(120, viewport_size.y - 10)
	
	var dialog_bg = ColorRect.new()
	dialog_bg.color = Color(0, 0, 0, 0.5)
	dialog_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(dialog_bg)
	
	var dialog = PanelContainer.new()
	dialog.custom_minimum_size = Vector2(dialog_width, dialog_height)
	dialog.size = Vector2(dialog_width, dialog_height)
	dialog.position = Vector2(
		(viewport_size.x - dialog_width) / 2,
		(viewport_size.y - dialog_height) / 2
	)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.08, 0.08, 0.95)
	style.border_color = Color(0.5, 0.25, 0.25, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	dialog.add_theme_stylebox_override("panel", style)
	canvas_layer.add_child(dialog)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)
	
	var title_label = Label.new()
	title_label.text = "❌ " + title
	title_label.add_theme_font_size_override("font_size", 9)
	title_label.add_theme_color_override("font_color", Color(1, 0.7, 0.7))
	vbox.add_child(title_label)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var msg_label = Label.new()
	msg_label.text = message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(dialog_width - 15, 0)
	msg_label.add_theme_font_size_override("font_size", 8)
	scroll.add_child(msg_label)
	
	var btn_container = HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_container)
	
	var close_btn = Button.new()
	close_btn.text = "確定"
	close_btn.custom_minimum_size = Vector2(45, 16)
	close_btn.add_theme_font_size_override("font_size", 8)
	btn_container.add_child(close_btn)
	
	var close_dialog = func():
		dialog_bg.queue_free()
		dialog.queue_free()
		_active_dialog = null
	
	close_btn.pressed.connect(close_dialog)
	dialog_bg.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			close_dialog.call()
	)
	
	dialog.set_meta("close_func", close_dialog)
	dialog.set_meta("dialog_bg", dialog_bg)
	_active_dialog = dialog

func _show_toast(message: String) -> void:
	"""顯示短暫提示 - 適應視口版"""
	print("📢 %s" % message)
	
	var viewport_size = get_viewport().get_visible_rect().size
	
	var toast = Label.new()
	toast.text = message
	toast.add_theme_font_size_override("font_size", 10)
	toast.add_theme_color_override("font_color", Color.WHITE)
	
	var toast_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	toast_panel.add_theme_stylebox_override("panel", style)
	toast_panel.add_child(toast)
	
	# 位置在視口頂部中間
	toast_panel.position = Vector2(
		(viewport_size.x - 150) / 2,
		10
	)
	
	canvas_layer.add_child(toast_panel)
	
	# 1.5秒後自動消失
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(toast_panel):
		toast_panel.queue_free()

# ===== 屬性面板 =====

var property_panel: PanelContainer = null

func _show_property_panel() -> void:
	if not current_agent_ref or not is_instance_valid(current_agent_ref):
		return
	
	if property_panel and is_instance_valid(property_panel):
		property_panel.queue_free()
		property_panel = null
		return
	
	var agent_data = _get_agent_data(current_agent_ref)
	
	property_panel = PanelContainer.new()
	property_panel.custom_minimum_size = Vector2(200, 320)
	property_panel.size = Vector2(200, 320)
	
	property_panel.position = Vector2(
		panel_container.position.x - 205,
		panel_container.position.y - 190
	)
	
	if property_panel.position.y < 10:
		property_panel.position.y = 10
	if property_panel.position.x < 10:
		property_panel.position.x = 10
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.95)
	style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	property_panel.add_theme_stylebox_override("panel", style)
	
	canvas_layer.add_child(property_panel)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	property_panel.add_child(margin)
	
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	var title_label = Label.new()
	title_label.text = "🤖 %s" % agent_data.name
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title_label)
	
	vbox.add_child(HSeparator.new())
	
	_add_property_item(vbox, "😊 心情", agent_data.mood)
	_add_property_item(vbox, "❤️ 健康", "%d/100" % agent_data.health)
	
	vbox.add_child(HSeparator.new())
	
	var schedule_label = Label.new()
	schedule_label.text = "📅 今日日程表"
	schedule_label.add_theme_font_size_override("font_size", 12)
	schedule_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(schedule_label)
	
	for item in agent_data.schedule:
		var item_label = Label.new()
		item_label.text = "%s %s %s" % [item.time, item.emoji, item.description]
		item_label.add_theme_font_size_override("font_size", 9)
		item_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		vbox.add_child(item_label)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	var close_btn = Button.new()
	close_btn.text = "關閉"
	close_btn.pressed.connect(_close_property_panel)
	vbox.add_child(close_btn)

func _close_property_panel() -> void:
	if property_panel and is_instance_valid(property_panel):
		property_panel.queue_free()
		property_panel = null

func _add_property_item(parent: VBoxContainer, label_text: String, value: String) -> void:
	var hbox = HBoxContainer.new()
	
	var label = Label.new()
	label.text = label_text + ":"
	label.custom_minimum_size = Vector2(90, 0)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	hbox.add_child(label)
	
	var value_label = Label.new()
	value_label.text = value
	value_label.add_theme_color_override("font_color", Color.WHITE)
	hbox.add_child(value_label)
	
	parent.add_child(hbox)

# ===== 數據獲取 =====

func _get_agent_data(agent: Node) -> Dictionary:
	var data = {
		"name": "Unknown",
		"id": 0,
		"mood": "neutral",
		"health": 100,
		"position": Vector2.ZERO,
		"state": "IDLE",
		"current_activity": "無",
		"schedule": []
	}
	
	if agent.has_method("get_status"):
		var status = agent.get_status()
		data.name = status.get("name", "Unknown")
		data.id = status.get("id", 0)
		data.mood = status.get("mood", "neutral")
		data.health = status.get("health", 100)
		data.position = status.get("position", Vector2.ZERO)
		data.state = status.get("state", "IDLE")
		data.current_activity = status.get("current_interaction_type", "無")
		if data.current_activity == "":
			data.current_activity = "無"
	else:
		if "agent_name" in agent:
			data.name = agent.agent_name
		if "agent_id" in agent:
			data.id = agent.agent_id
		if "mood" in agent:
			data.mood = agent.mood
		if "health" in agent:
			data.health = agent.health
		if "global_position" in agent:
			data.position = agent.global_position
	
	data.schedule = _get_agent_schedule(data.id)
	return data

func _get_agent_schedule(agent_id: int) -> Array:
	var schedule = []
	var world = get_parent()
	
	if world:
		var schedule_data = []
		if agent_id == 1 and "agent1_schedule" in world:
			schedule_data = world.agent1_schedule
		elif agent_id == 2 and "agent2_schedule" in world:
			schedule_data = world.agent2_schedule
		
		for item in schedule_data:
			schedule.append({
				"time": _format_time(item.time),
				"description": item.description,
				"emoji": item.get("emoji", "")
			})
	
	return schedule

func _format_time(minutes: int) -> String:
	var hh = minutes / 60
	var mm = minutes % 60
	return "%02d:%02d" % [hh, mm]

# ===== 按鍵處理 =====

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			# 優先關閉活動對話框
			if _active_dialog and is_instance_valid(_active_dialog):
				var close_func = _active_dialog.get_meta("close_func", Callable())
				if close_func.is_valid():
					close_func.call()
				else:
					var dialog_bg = _active_dialog.get_meta("dialog_bg", null)
					if dialog_bg and is_instance_valid(dialog_bg):
						dialog_bg.queue_free()
					_active_dialog.queue_free()
				_active_dialog = null
				get_viewport().set_input_as_handled()
				return
			
			# 然後關閉桌寵
			if is_deskpet_open():
				close_deskpet()
				get_viewport().set_input_as_handled()
				return
		
		elif event.keycode == KEY_F9:
			if is_deskpet_open():
				close_deskpet()
				get_viewport().set_input_as_handled()
