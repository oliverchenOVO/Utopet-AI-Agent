#speak_window.gd
extends Window

@onready var input_field: LineEdit = $Panel/VBoxContainer/HBoxContainer/input_field
@onready var send_button: Button = $Panel/VBoxContainer/HBoxContainer/SendButton
@onready var history_button: Button = $Panel/VBoxContainer/HBoxContainer/HistoryButton
@onready var attach_button: Button = $Panel/VBoxContainer/AttachButton
@onready var image_preview_container: HBoxContainer = $Panel/VBoxContainer/ImagePreviewContainer
@onready var image_name_label: Label = $Panel/VBoxContainer/ImagePreviewContainer/ImageNameLabel
@onready var clear_image_button: Button = $Panel/VBoxContainer/ImagePreviewContainer/ClearImageButton
@onready var history_scroll: ScrollContainer = $Panel/VBoxContainer/HistoryScroll
@onready var history_message_container: VBoxContainer = $Panel/VBoxContainer/HistoryScroll/HistoryMessages
var schedule_request: HTTPRequest = null

signal message_sent(message: String)
signal ai_response_received(response: String)
signal ai_stream_done(full_response: String)
signal loading_started()
signal loading_finished()
signal error_occurred(error_message: String)
signal emotion_triggered(emotion_name: String)

var http_image_request: HTTPRequest

const IMAGE_URL = "http://127.0.0.1:8000/chat_with_image"

const VOICE_STREAM_HOST = "127.0.0.1"
const VOICE_STREAM_PORT = 8000
const VOICE_STREAM_PATH = "/voice_chat_stream?session_id=default&timeout=10.0"

const CHAT_STREAM_HOST = "127.0.0.1"
const CHAT_STREAM_PORT = 8000
const CHAT_STREAM_PATH = "/chat_stream"

# ── Memory API 設定 ──────────────────────────────────────
const MEMORY_BASE_URL = "http://127.0.0.1:8000/memory"  # 所有記憶端點的 base URL

var history_scene = preload("res://Scene/history_window.tscn")

var pending_image_base64: String = ""
var pending_image_name: String = ""
var file_dialog: FileDialog

# ── SSE 串流狀態 ──────────────────────────────────────────
var _sse_client: HTTPClient = null
var _sse_active: bool = false
var _sse_buffer: String = ""
var _ai_reply_buffer: String = ""
var _streaming_label: RichTextLabel = null  # 串流中的臨時 AI 訊息 label

# ── Memory HTTP Request 節點（每種操作各一個，避免衝突）──
var _http_memory_get: HTTPRequest    # GET  /memory        讀取所有記憶
var _http_memory_post: HTTPRequest   # POST /memory        新增/更新記憶
var _http_memory_delete: HTTPRequest # DELETE /memory/{key} 刪除記憶


func _ready():
	visible = false
	close_requested.connect(hide)

	http_image_request = HTTPRequest.new()
	http_image_request.timeout = 60.0
	add_child(http_image_request)
	http_image_request.request_completed.connect(_on_image_request_completed)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.bmp,*.webp ; 圖片檔案"])
	file_dialog.size = Vector2i(800, 600)
	file_dialog.file_selected.connect(_on_image_file_selected)
	add_child(file_dialog)

	image_preview_container.visible = false
	load_history()

	attach_button.pressed.connect(_on_attach_button_pressed)
	clear_image_button.pressed.connect(_on_clear_image_pressed)
	history_button.pressed.connect(_on_history_button_pressed)
	send_button.pressed.connect(_on_send_button_pressed)
	
	if is_instance_valid(input_field):
		# 1. 檢查如果編輯器 UI 或其他地方已經連過線，先強行拔掉
		if input_field.text_submitted.is_connected(_on_input_field_text_submitted):
			input_field.text_submitted.disconnect(_on_input_field_text_submitted)
		# 2. 確保乾乾淨淨地連上我們程式碼控制的這條線
		input_field.text_submitted.connect(_on_input_field_text_submitted)
	if schedule_request:
		schedule_request.request_completed.connect(_on_schedule_request_completed)

	# ── 初始化 Memory HTTP 節點 ──────────────────────────
	_http_memory_get = HTTPRequest.new()
	_http_memory_get.timeout = 10.0
	add_child(_http_memory_get)
	_http_memory_get.request_completed.connect(_on_memory_get_completed)

	_http_memory_post = HTTPRequest.new()
	_http_memory_post.timeout = 10.0
	add_child(_http_memory_post)
	_http_memory_post.request_completed.connect(_on_memory_post_completed)
	_init_schedule_http_request()
	_http_memory_delete = HTTPRequest.new()
	_http_memory_delete.timeout = 10.0
	add_child(_http_memory_delete)
	_http_memory_delete.request_completed.connect(_on_memory_delete_completed)
	_connect_to_character()
	
func _init_schedule_http_request() -> void:
	# 動態實例化一個全新的 HTTPRequest 節點
	schedule_request = HTTPRequest.new()
	# 將它添加為 speak_window 的子節點
	add_child(schedule_request)
	# 連接請求完成的訊號
	schedule_request.request_completed.connect(_on_schedule_request_completed)
	print("✅ [SpeakWindow] 日程表 HTTP 節點動態建立成功！")
	
func _connect_to_character() -> void:
	var main_window = get_tree().root.get_node_or_null("MainWindow")
	if main_window:
		var character = main_window.get_node_or_null("Character")
		if character and character.has_method("play_emotion_animation"):
			# 如果還沒連線，就立刻連上桌寵的播放動畫函數
			if not emotion_triggered.is_connected(character.play_emotion_animation):
				emotion_triggered.connect(character.play_emotion_animation)
				print("✅ [SpeakWindow 內部連線成功] 已成功鎖定桌寵物件！")

func _on_schedule_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var json = JSON.new()
		var parse_err = json.parse(body.get_string_from_utf8())
		if parse_err == OK:
			var response = json.get_data()
			if response.has("schedule_content"):
				var content = response["schedule_content"]
				
				Global.add_history("ai", content)
				load_history()
				print("✅ [Schedule] 日程表已成功載入至 speak_window")
	else:
		print("❌ [Schedule] 後端回傳錯誤碼: ", response_code)

func show_window():
	visible = true
	popup_centered()
	grab_focus()
	load_history()
	input_field.grab_focus()

func show_dialog():
	show_window()

func hide_window():
	visible = false
	input_field.text = ""
	clear_pending_image()
# ════════════════════════════════════════════════════════════
# ── Memory API ──────────────────────────────────────────────
# ════════════════════════════════════════════════════════════

# ── 讀取所有記憶（GET /memory）──────────────────────────────
# 呼叫後非同步等待，結果在 _on_memory_get_completed 處理
func memory_get_all():
	var err = _http_memory_get.request(MEMORY_BASE_URL)
	if err != OK:
		push_error("[memory] GET 請求失敗，錯誤碼：" + str(err))


func _on_memory_get_completed(_result, response_code, _headers, body):
	if response_code != 200:
		push_error("[memory] GET 回應錯誤：" + str(response_code))
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("[memory] GET 回應解析失敗")
		return

	var memories: Array = json.data.get("memories", [])

	# 印到 console 方便除錯
	print("═══════════════════ 記憶列表 ═══════════════════")
	if memories.is_empty():
		print("（目前沒有記憶）")
	else:
		for m in memories:
			var tag = "⭐永久" if m["importance"] == "important" else "⏳短期"
			print("[%s] %s：%s　（更新於 %s）" % [tag, m["key"], m["value"], m["updated_at"]])
	print("════════════════════════════════════════════════")


# ── 新增或更新記憶（POST /memory）───────────────────────────
# key        : 記憶類別，例如 "使用者名字"
# value      : 記憶內容，例如 "Johnny"
# importance : "important"（永久）或 "normal"（7天後老化）
func memory_add(key: String, value: String, importance: String = "normal"):
	var body = JSON.stringify({
		"key":        key,
		"value":      value,
		"importance": importance
	})
	var headers = ["Content-Type: application/json"]
	var err = _http_memory_post.request(MEMORY_BASE_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("[memory] POST 請求失敗，錯誤碼：" + str(err))


func _on_memory_post_completed(_result, response_code, _headers, body):
	if response_code != 200:
		push_error("[memory] POST 回應錯誤：" + str(response_code))
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK:
		print("[memory] ", json.data.get("message", "儲存成功"))


# ── 刪除記憶（DELETE /memory/{key}）────────────────────────
# key：要刪除的記憶類別，例如 "使用者名字"
func memory_delete(key: String):
	# URL encode key 避免中文或空格造成錯誤
	var url = MEMORY_BASE_URL + "/" + key.uri_encode()
	var err = _http_memory_delete.request(url, [], HTTPClient.METHOD_DELETE)
	if err != OK:
		push_error("[memory] DELETE 請求失敗，錯誤碼：" + str(err))


func _on_memory_delete_completed(_result, response_code, _headers, body):
	if response_code != 200:
		push_error("[memory] DELETE 回應錯誤：" + str(response_code))
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK:
		print("[memory] ", json.data.get("message", "刪除成功"))


# ════════════════════════════════════════════════════════════
# ── 以下為原有程式碼（未修改）───────────────────────────────
# ════════════════════════════════════════════════════════════

# ── 圖片 ────────────────────────────────────────────────

func _on_attach_button_pressed():
	file_dialog.popup_centered()

func _on_image_file_selected(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		error_occurred.emit("無法開啟圖片：" + path)
		return
	var bytes = file.get_buffer(file.get_length())
	file.close()
	pending_image_base64 = Marshalls.raw_to_base64(bytes)
	pending_image_name   = path.get_file()
	image_name_label.text = "📎 " + pending_image_name
	image_preview_container.visible = true

func _on_clear_image_pressed():
	clear_pending_image()

func clear_pending_image():
	pending_image_base64 = ""
	pending_image_name   = ""
	image_name_label.text = ""
	image_preview_container.visible = false

# ── 送出文字訊息 ─────────────────────────────────────────

func send_message():
	var message = input_field.text.strip_edges()
	if message.length() == 0 and pending_image_base64 == "":
		return

	var display_message = message
	if pending_image_name != "":
		display_message = ("" if message == "" else message + "\n") + "📎 " + pending_image_name
	message_sent.emit(display_message)
	Global.add_history("user", display_message)
	load_history()

	input_field.text = ""
	input_field.grab_focus()

	if not Global.is_ai_enabled:
		var sys_msg = "(AI 目前已關閉)"
		ai_response_received.emit(sys_msg)
		ai_stream_done.emit(sys_msg)
		Global.add_history("ai", sys_msg)
		load_history()
		clear_pending_image()
		return

	loading_started.emit()
	send_button.disabled = true

	if pending_image_base64 != "":
		send_image_request(message, pending_image_base64)
		clear_pending_image()
	else:
		_start_chat_stream(message)

# ── 圖片請求 ─────────────────────────────────────────────

func send_image_request(message: String, image_b64: String):
	var json_data = {
		"message": message if message != "" else "幫我辨識並統整這張圖片的文字",
		"image_base64": image_b64,
		"mode": "ocr_then_llm"
	}
	var headers = ["Content-Type: application/json", "Accept: application/json"]
	var err = http_image_request.request(IMAGE_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(json_data))
	if err != OK:
		error_occurred.emit("無法發送圖片請求")
		send_button.disabled = false
		loading_finished.emit()

func _on_image_request_completed(_result, response_code, _headers, body):
	send_button.disabled = false
	loading_finished.emit()
	if response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.data
			if data.has("success") and data["success"]:
				var resp = data["response"]
				ai_response_received.emit(resp)
				ai_stream_done.emit(resp)
				Global.add_history("ai", resp)
				load_history()
			else:
				error_occurred.emit(data.get("error", "未知錯誤"))
		else:
			error_occurred.emit("無法解析服務器回應")
	else:
		error_occurred.emit("服務器回應代碼 " + str(response_code))

# ── SSE 文字串流 /chat_stream ────────────────────────────

func _start_chat_stream(message: String):
	_sse_stop()
	_ai_reply_buffer = ""
	ai_response_received.emit("")
	_create_streaming_label()

	var body = JSON.stringify({
		"message": message,
		"session_id": "default",
		"temperature": 0.7,
		"max_tokens": 512
	})

	_sse_client = HTTPClient.new()
	_sse_client.connect_to_host(CHAT_STREAM_HOST, CHAT_STREAM_PORT)
	_sse_active = true
	_sse_buffer = ""
	set_meta("_sse_mode", "chat")
	set_meta("_sse_body", body)
	set_meta("_sse_requested", false)

# ── SSE 語音串流 /voice_chat_stream ──────────────────────

func _on_speak_pressed() -> void:
	if _sse_active:
		return

	_sse_stop()
	_ai_reply_buffer = ""
	loading_started.emit()
	send_button.disabled = true
	input_field.placeholder_text = "聆聽中...請說話"
	input_field.editable = false

	_sse_client = HTTPClient.new()
	_sse_client.connect_to_host(VOICE_STREAM_HOST, VOICE_STREAM_PORT)
	_sse_active = true
	_sse_buffer = ""
	set_meta("_sse_mode", "voice")
	set_meta("_sse_requested", false)
	_create_streaming_label()

# ── _process：每幀輪詢 SSE ────────────────────────────────

func _process(_delta):
	if not _sse_active or _sse_client == null:
		return

	_sse_client.poll()
	var status = _sse_client.get_status()

	match status:
		HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING:
			pass

		HTTPClient.STATUS_CONNECTED:
			if not get_meta("_sse_requested", false):
				set_meta("_sse_requested", true)
				var sse_mode = get_meta("_sse_mode", "voice")
				var headers = ["Accept: text/event-stream", "Cache-Control: no-cache"]
				if sse_mode == "voice":
					_sse_client.request(HTTPClient.METHOD_GET, VOICE_STREAM_PATH, headers)
				else:
					headers.append("Content-Type: application/json")
					_sse_client.request(
						HTTPClient.METHOD_POST,
						CHAT_STREAM_PATH,
						headers,
						get_meta("_sse_body", "{}")
					)

		HTTPClient.STATUS_REQUESTING:
			pass

		HTTPClient.STATUS_BODY:
					var chunk = _sse_client.read_response_body_chunk()
					while chunk.size() > 0:
						_sse_buffer += chunk.get_string_from_utf8()
						_parse_sse_buffer()
						if _sse_client == null:
							return
						chunk = _sse_client.read_response_body_chunk()
		_:
			_on_sse_ended()

# ── SSE 解析 ─────────────────────────────────────────────

func _parse_sse_buffer():
	while "\n\n" in _sse_buffer:
		var idx = _sse_buffer.find("\n\n")
		var block = _sse_buffer.left(idx)
		_sse_buffer = _sse_buffer.substr(idx + 2)
		_handle_sse_block(block)

func _handle_sse_block(block: String):
	var event_type = "token"
	var data = ""

	for line in block.split("\n"):
		if line.begins_with("event: "):
			event_type = line.substr(7).strip_edges()
		elif line.begins_with("data: "):
			data = line.substr(6)

	match event_type:
		"asr_result":
			print("🎤 辨識：", data)
			input_field.placeholder_text = "輸入訊息..."
			input_field.editable = true
			message_sent.emit(data)
			Global.add_history("user", data)
			load_history()
			ai_response_received.emit("")

		"token":
			var token = data.replace("\\n", "\n")
			_ai_reply_buffer += token
			ai_response_received.emit(_ai_reply_buffer)
			_update_streaming_label(_ai_reply_buffer)

		"done":
			if _ai_reply_buffer != "":
				var emotion = parse_emotion(_ai_reply_buffer)
				if emotion != "":
					print("🎯 [SpeakWindow] 偵測到情緒標籤：", emotion)
					emotion_triggered.emit(emotion) 
				var clean_text = _ai_reply_buffer
				for emotion_tag in ["[快樂]", "[難過]", "[生氣]", "[害怕]"]:
					clean_text = clean_text.replace(emotion_tag, "")
				clean_text = clean_text.strip_edges()
				_remove_streaming_label()        # ← 先移除臨時 label
				Global.add_history("ai", clean_text)
				load_history()
				
				ai_stream_done.emit(clean_text)
			else:
				_remove_streaming_label()
			_on_sse_ended()

func _on_sse_ended():
	_sse_stop()
	send_button.disabled = false
	loading_finished.emit()
	input_field.placeholder_text = "輸入訊息..."
	input_field.editable = true

func _sse_stop():
	_sse_active = false
	if _sse_client != null:
		_sse_client.close()
		_sse_client = null
	_sse_buffer = ""

# ── 串流臨時 Label 管理 ───────────────────────────────────

func _create_streaming_label():
	_remove_streaming_label()  # 防止重複
	if not is_instance_valid(history_message_container):
		return
	_streaming_label = RichTextLabel.new()
	_streaming_label.fit_content = true
	_streaming_label.bbcode_enabled = true
	_streaming_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_streaming_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_streaming_label.custom_minimum_size = Vector2(560, 0)
	_streaming_label.text = "[color=#00FFFF][AI]:[/color] ▋"  # 游標佔位
	history_message_container.add_child(_streaming_label)
	await get_tree().process_frame
	_scroll_history_to_bottom()

func _update_streaming_label(full_text: String):
	if not is_instance_valid(_streaming_label):
		return
	# 顯示目前累積文字 + 游標
	_streaming_label.text = "[color=#00FFFF][AI]:[/color] " + full_text + "▋"
	_scroll_history_to_bottom()

func _remove_streaming_label():
	if is_instance_valid(_streaming_label):
		_streaming_label.queue_free()
	_streaming_label = null

# ── 歷史記錄 ─────────────────────────────────────────────

func load_history():
	if not is_instance_valid(history_message_container):
		return

	for child in history_message_container.get_children():
		child.queue_free()

	for log_data in Global.chat_history:
		add_history_message(log_data)

	await get_tree().process_frame
	_scroll_history_to_bottom()

func add_history_message(data: Dictionary):
	var label = RichTextLabel.new()
	label.fit_content = true
	label.bbcode_enabled = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(560, 0)

	var time_str = "[color=#888888][" + data.get("time", "") + "][/color] "
	var text = str(data.get("text", ""))

	if data.get("role", "") == "user":
		label.text = time_str + "[color=#FFFF00][你]:[/color] " + text
	else:
		label.text = time_str + "[color=#00FFFF][AI]:[/color] " + text

	label.text += "\n[color=#333333]________________________[/color]"
	history_message_container.add_child(label)

func _scroll_history_to_bottom():
	if not is_instance_valid(history_scroll):
		return
	history_scroll.scroll_vertical = int(history_scroll.get_v_scroll_bar().max_value)	

func _on_history_button_pressed():
	load_history()

func _on_send_button_pressed():
	send_message()

func _on_input_field_text_submitted(_new_text):
	send_message()
func parse_emotion(text: String) -> String:
	var start_idx = text.find("[")
	var end_idx = text.find("]")
	
	# 檢查是否包含完整的中括號
	if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
		var emotion_word = text.substr(start_idx + 1, end_idx - start_idx - 1)
		# 檢查是否為指定的四種情緒
		if emotion_word in ["快樂", "難過", "生氣", "害怕"]:
			return emotion_word
	return ""


func _on_schedule_pressed() -> void:
	pass # Replace with function body.
