extends PopupMenu

var dialog_box: Control
var settings_window_scene = preload("res://Scene/setting.tscn")
var speak_window_scene = preload("res://Scene/speak_window.tscn")
var character_setting_scene = preload("res://Scene/character_setting.tscn")
var settings_window = null 
var speak_window = null
var character_setting = null 

var http_request: HTTPRequest
const BASE_URL = "http://127.0.0.1:8000"

func _ready():
	visible = false
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func set_dialog_box(box: Control):
	dialog_box = box

func _on_index_pressed(id: int):
	match id:
		0: _on_speaknow_window()
		1: _on_character_pressed()
		2: _on_button_pressed()

# --- 清場函數 ---
func _close_all_windows():
	# 關閉對話框
	if dialog_box: dialog_box.visible = false
	
	# ★ 關閉 Internet (直接找 MainWindow 裡的節點)
	var main = get_tree().root.get_node("MainWindow")
	var internet = main.get_node_or_null("internet") # 請確認節點名稱
	if internet: internet.visible = false
	
	# 關閉設定
	if settings_window: settings_window.visible = false
	if speak_window: speak_window.visible = false
	if character_setting: character_setting.visible = false

# --- 按鈕功能 ---
func _on_speaknow_window():
	visible = false
	_close_all_windows()

	var main_window = get_tree().root.get_node("MainWindow")

	if not speak_window:
		speak_window = speak_window_scene.instantiate()
		main_window.add_child(speak_window)

		speak_window.message_sent.connect(main_window._on_dialog_box_message_sent)
		speak_window.ai_response_received.connect(main_window._on_ai_response_received)
		speak_window.ai_stream_done.connect(main_window._on_ai_stream_done)
		speak_window.loading_started.connect(main_window._on_loading_started)
		speak_window.loading_finished.connect(main_window._on_loading_finished)
		speak_window.error_occurred.connect(main_window._on_error_occurred)
		speak_window.visibility_changed.connect(main_window._update_mouse_passthrough_polygon)
	
	if speak_window.has_method("show_window"):
		speak_window.show_window()
	else:
		speak_window.popup_centered()

	main_window.call_deferred("_update_mouse_passthrough_polygon")

func _on_speak_pressed():
	visible = false
	_close_all_windows()
	if dialog_box: dialog_box.show_dialog()

func _on_internet_pressed():
	print("開啟網頁分析視窗")
	visible = false
	_close_all_windows() # 先把別人關掉
	
	# ★ 直接找 MainWindow 裡的 Internet 節點把它打開
	var main = get_tree().root.get_node("MainWindow")
	var internet = main.get_node_or_null("internet")
	
	if internet:
		internet.visible = true
		internet.move_to_front() # 讓它顯示在最上層
		# 觸發主畫面更新穿透區域
		if main.has_method("_update_mouse_passthrough_polygon"):
			main._update_mouse_passthrough_polygon()
	else:
		print("錯誤：找不到 Internet 節點，請確認你有把它拉進 MainWindow 場景並命名為 Internet")

func _on_settings_button_pressed():
	visible = false
	_close_all_windows()
	
	var main_window = get_tree().root.get_node("MainWindow")
	if not settings_window:
		settings_window = settings_window_scene.instantiate()
		main_window.add_child(settings_window)
		settings_window.visibility_changed.connect(main_window._update_mouse_passthrough_polygon)
	
	settings_window.show_window()
	main_window.call_deferred("_update_mouse_passthrough_polygon")

func _on_character_pressed():
	visible = false
	_close_all_windows()
	var main_window = get_tree().root.get_node("MainWindow")
	if not character_setting:
		character_setting = character_setting_scene.instantiate()
		main_window.add_child(character_setting)
		character_setting.visibility_changed.connect(main_window._update_mouse_passthrough_polygon)
	
	character_setting.popup_centered()
	main_window.call_deferred("_update_mouse_passthrough_polygon")

# ... (其他函數保持不變) ...

func _on_emotion_pressed(): visible = false
func _on_calc_pressed(): 
	OS.execute("calc.exe", [])
	visible = false
func _on_weather_pressed(): 
	OS.shell_open("https://www.cwa.gov.tw/V8/C/W/OBS_Map.html")
	visible = false # 點擊後關閉右鍵選單
func _on_translate_pressed(): print("翻譯 - 待實作")
func _on_mouth_pressed(): print("語音辨識，已經在dialogbox那邊")
func _on_button_pressed(): get_tree().quit()

func _on_pic_to_word_pressed():
	print("圖片辨識")
	if http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	http_request.request(BASE_URL + "/open_ocr", ["Content-Type: application/json"], HTTPClient.METHOD_POST, "{}")

@warning_ignore("unused_parameter")
func _on_request_completed(result, response_code, headers, body):
	if response_code == 200: print("✅ 指令發送成功")
	else: print("❌ 連線失敗，狀態碼：", response_code)
