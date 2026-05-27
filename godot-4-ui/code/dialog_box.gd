extends Control

@onready var input_field: LineEdit = $Panel/VBoxContainer/HBoxContainer/input_field
@onready var send_button: Button = $Panel/VBoxContainer/HBoxContainer/SendButton
@onready var history_button: Button = $Panel/VBoxContainer/HBoxContainer/HistoryButton
# @onready var speak_button: Button = $Panel/VBoxContainer/HBoxContainer/SpeakButton 

signal message_sent(message: String)
signal ai_response_received(response: String)
signal loading_started()
signal loading_finished()
signal error_occurred(error_message: String)

var http_request: HTTPRequest       # 負責 AI 聊天
var http_voice_request: HTTPRequest # 負責語音聽寫

const SERVER_URL = "http://127.0.0.1:8000/chat"
const VOICE_URL = "http://127.0.0.1:8000/listen"

# ★ 新增：預載歷史紀錄視窗場景 (請確保路徑正確)
var history_scene = preload("res://Scene/history_window.tscn")

func _ready():
	visible = false
	
	# 初始化 AI 聊天用的請求節點
	http_request = HTTPRequest.new()
	http_request.timeout = 60.0
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# 初始化語音用的請求節點
	http_voice_request = HTTPRequest.new()
	http_voice_request.timeout = 15.0
	add_child(http_voice_request)
	http_voice_request.request_completed.connect(_on_voice_request_completed)

	# 連接按鈕信號 (如果編輯器沒接，這裡可以用程式接)
	if not history_button.pressed.is_connected(_on_history_button_pressed):
		history_button.pressed.connect(_on_history_button_pressed)
	if not send_button.pressed.is_connected(_on_send_button_pressed):
		send_button.pressed.connect(_on_send_button_pressed)

func show_dialog():
	visible = true
	input_field.grab_focus()

func hide_dialog():
	visible = false
	input_field.text = ""

func send_message():
	var message = input_field.text.strip_edges()
	if message.length() > 0:
		# 1. 顯示並紀錄玩家訊息
		message_sent.emit(message)
		Global.add_history("user", message) # ★ 存入歷史紀錄
		
		input_field.text = ""
		input_field.grab_focus()
		
		# ★ 2. 檢查 GlobalState：AI 是否開啟？
		if not Global.is_ai_enabled:
			# 如果 AI 沒開，回傳一個系統提示，不發送網路請求
			var sys_msg = "(AI 目前已關閉)"
			ai_response_received.emit(sys_msg)
			Global.add_history("ai", sys_msg)
			return
		
		# 3. 如果開啟，才發送請求
		loading_started.emit()
		send_button.disabled = true
		send_http_request(message)

func send_http_request(message: String):
	var json_data = {
		"message": message,
		"temperature": 0.7,
		"max_tokens": 1000
	}
	var json_string = JSON.stringify(json_data)
	
	var headers = [
		"Content-Type: application/json",
		"Accept: application/json"
	]
	
	var error = http_request.request(SERVER_URL, headers, HTTPClient.METHOD_POST, json_string)
	
	if error != OK:
		error_occurred.emit("無法發送請求")
		send_button.disabled = false
		loading_finished.emit()

# --- AI 回應處理 ---
func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	send_button.disabled = false
	loading_finished.emit()
	
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		
		if parse_result == OK:
			var response_data = json.data
			if response_data.has("success") and response_data["success"]:
				var ai_response = response_data["response"]
				
				# 顯示回應
				ai_response_received.emit(ai_response)
				# 存入歷史紀錄
				Global.add_history("ai", ai_response)
				
			else:
				var error_msg = response_data.get("error", "未知錯誤")
				error_occurred.emit(error_msg)
		else:
			error_occurred.emit("無法解析服務器回應")
	else:
		error_occurred.emit("服務器回應代碼 " + str(response_code))

# --- 語音按鈕處理 ---
func _on_speak_pressed() -> void:
	loading_started.emit() 
	input_field.placeholder_text = "聆聽中...請說話"
	input_field.editable = false
	
	var error = http_voice_request.request(VOICE_URL, [], HTTPClient.METHOD_POST)
	
	if error != OK:
		loading_finished.emit()
		input_field.placeholder_text = "輸入訊息..."
		input_field.editable = true
		error_occurred.emit("無法連接語音服務")

func _on_voice_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	loading_finished.emit()
	input_field.placeholder_text = "輸入訊息..."
	input_field.editable = true
	input_field.grab_focus()
	
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		
		if parse_result == OK:
			var data = json.data
			if data.has("success") and data["success"]:
				var text = data["text"]
				if text != "":
					input_field.text = text
				else:
					print("未偵測到語音")
			else:
				error_occurred.emit(data.get("error", "語音識別錯誤"))
		else:
			error_occurred.emit("無法解析語音資料")
	else:
		error_occurred.emit("語音服務連線失敗: " + str(response_code))

# 歷史紀錄按鈕
func _on_history_button_pressed():
	print("開啟歷史紀錄視窗")
	# 實例化歷史視窗
	var history_window = history_scene.instantiate()
	# 將其加入到場景樹的根節點 (這樣可以獨立於 DialogBox 顯示)
	get_tree().root.add_child(history_window)
	history_window.show()

# --- 其他 UI 事件 ---
func _on_send_button_pressed():
	send_message()

func _on_input_field_text_submitted(_new_text):
	send_message()
