# python_api_client.gd - 統一的Python API客戶端 v2.1
# 負責與Python FastAPI服務器通信
extends Node

# ===== API配置 =====
const PYTHON_API_BASE = "http://127.0.0.1:8000"

# ===== 信號 =====
signal api_response_received(endpoint: String, success: bool, data: Dictionary)
signal api_error(endpoint: String, error: String)

# OCR相關信號
signal ocr_window_opened()

# 語音相關信號
signal speech_started()
signal speech_result_received(text: String)
signal speech_error(error: String)

# 摘要相關信號
signal summary_received(summary: String, points: Array)

# 聊天相關信號
signal chat_response_received(response: String)

# 計算器相關信號
signal calculate_result_received(result: String)
signal calculator_opened()

# ===== HTTP請求組件 =====
var http_requests: Dictionary = {}

func _ready() -> void:
	print("🐍 Python API客戶端 v2.1 初始化完成")
	print("📡 API服務器地址: %s" % PYTHON_API_BASE)

# ===== 創建HTTP請求 =====

func _create_http_request(request_id: String) -> HTTPRequest:
	"""創建一個新的HTTP請求組件"""
	if request_id in http_requests:
		var old_request = http_requests[request_id]
		if is_instance_valid(old_request):
			old_request.queue_free()
	
	var http = HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)
	http_requests[request_id] = http
	return http

func _cleanup_http_request(request_id: String) -> void:
	"""清理HTTP請求組件"""
	if request_id in http_requests:
		var http = http_requests[request_id]
		if is_instance_valid(http):
			http.queue_free()
		http_requests.erase(request_id)

# ===== 健康檢查 =====

func check_server_health(callback: Callable = Callable()) -> void:
	"""檢查Python服務器是否運行"""
	var http = _create_http_request("health")
	http.request_completed.connect(_on_health_check_completed.bind(callback))
	
	var error = http.request(PYTHON_API_BASE + "/health")
	if error != OK:
		push_warning("❌ 健康檢查請求失敗: %d" % error)
		if callback.is_valid():
			callback.call(false, "請求發送失敗")

func _on_health_check_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, callback: Callable) -> void:
	_cleanup_http_request("health")
	
	if code == 200:
		print("✅ Python API服務器運行正常")
		if callback.is_valid():
			callback.call(true, "")
	else:
		print("❌ Python API服務器未響應 (Code: %d)" % code)
		if callback.is_valid():
			callback.call(false, "服務器未響應")

# ===== OCR功能 =====

func open_ocr_window() -> void:
	"""打開OCR識別視窗"""
	print("📷 正在打開OCR視窗...")
	
	var http = _create_http_request("ocr")
	http.request_completed.connect(_on_ocr_window_completed)
	
	var headers = ["Content-Type: application/json"]
	var error = http.request(
		PYTHON_API_BASE + "/open_ocr",
		headers,
		HTTPClient.METHOD_POST,
		"{}"
	)
	
	if error != OK:
		push_warning("❌ OCR請求失敗: %d" % error)
		api_error.emit("ocr", "請求發送失敗")

func _on_ocr_window_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_cleanup_http_request("ocr")
	
	if code == 200:
		var response = _parse_json_response(body)
		if response.get("success", false):
			print("✅ OCR視窗已打開")
			ocr_window_opened.emit()
		else:
			print("❌ OCR視窗打開失敗: %s" % response.get("error", "未知錯誤"))
			api_error.emit("ocr", response.get("error", "未知錯誤"))
	else:
		print("❌ OCR請求失敗 (Code: %d)" % code)
		api_error.emit("ocr", "HTTP錯誤: %d" % code)

# ===== 語音識別功能 =====

func start_speech_recognition() -> void:
	"""開始語音識別"""
	print("🎤 正在啟動語音識別...")
	speech_started.emit()
	
	var http = _create_http_request("speech")
	http.request_completed.connect(_on_speech_completed)
	http.timeout = 15.0
	
	var headers = ["Content-Type: application/json"]
	var error = http.request(
		PYTHON_API_BASE + "/listen",
		headers,
		HTTPClient.METHOD_POST,
		"{}"
	)
	
	if error != OK:
		push_warning("❌ 語音識別請求失敗: %d" % error)
		speech_error.emit("請求發送失敗")

func _on_speech_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_cleanup_http_request("speech")
	
	if code == 200:
		var response = _parse_json_response(body)
		if response.get("success", false):
			var text = response.get("text", "")
			print("✅ 語音識別結果: %s" % text)
			speech_result_received.emit(text)
		else:
			var error_msg = response.get("error", "識別失敗")
			print("❌ 語音識別失敗: %s" % error_msg)
			speech_error.emit(error_msg)
	else:
		print("❌ 語音識別請求失敗 (Code: %d)" % code)
		speech_error.emit("HTTP錯誤: %d" % code)

# ===== AI聊天功能 =====

func send_chat_message(message: String, temperature: float = 0.7, max_tokens: int = 4000) -> void:
	"""發送聊天消息到AI"""
	print("💬 發送消息: %s" % message)
	
	var http = _create_http_request("chat")
	http.request_completed.connect(_on_chat_completed)
	http.timeout = 60.0
	
	var payload = {
		"message": message,
		"temperature": temperature,
		"max_tokens": max_tokens
	}
	
	var headers = ["Content-Type: application/json"]
	var error = http.request(
		PYTHON_API_BASE + "/chat",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	
	if error != OK:
		push_warning("❌ 聊天請求失敗: %d" % error)
		api_error.emit("chat", "請求發送失敗")

func _on_chat_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_cleanup_http_request("chat")
	
	if code == 200:
		var response = _parse_json_response(body)
		if response.get("success", false):
			var ai_response = response.get("response", "")
			print("✅ AI回應: %s" % ai_response)
			chat_response_received.emit(ai_response)
		else:
			var error_msg = response.get("error", "聊天失敗")
			print("❌ 聊天失敗: %s" % error_msg)
			api_error.emit("chat", error_msg)
	else:
		print("❌ 聊天請求失敗 (Code: %d)" % code)
		api_error.emit("chat", "HTTP錯誤: %d" % code)

# ===== 摘要功能 =====

func summarize_news(title: String, text: String) -> void:
	"""新聞摘要"""
	print("📰 正在生成新聞摘要...")
	_send_summary_request("/summarize/news", title, text)

func summarize_article(title: String, text: String) -> void:
	"""文章摘要"""
	print("📄 正在生成文章摘要...")
	_send_summary_request("/summarize/article", title, text)

func _send_summary_request(endpoint: String, title: String, text: String) -> void:
	"""發送摘要請求"""
	var http = _create_http_request("summary")
	http.request_completed.connect(_on_summary_completed)
	http.timeout = 30.0
	
	var payload = {
		"title": title,
		"text": text
	}
	
	var headers = ["Content-Type: application/json"]
	var error = http.request(
		PYTHON_API_BASE + endpoint,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	
	if error != OK:
		push_warning("❌ 摘要請求失敗: %d" % error)
		api_error.emit("summary", "請求發送失敗")

func _on_summary_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_cleanup_http_request("summary")
	
	if code == 200:
		var response = _parse_json_response(body)
		if response.get("success", false):
			var summary = response.get("summary", "")
			var points = response.get("points", [])
			print("✅ 摘要生成完成")
			summary_received.emit(summary, points)
		else:
			var error_msg = response.get("error", "摘要生成失敗")
			print("❌ 摘要失敗: %s" % error_msg)
			api_error.emit("summary", error_msg)
	else:
		print("❌ 摘要請求失敗 (Code: %d)" % code)
		api_error.emit("summary", "HTTP錯誤: %d" % code)

# ===== 計算器功能 =====

func calculate_expression(expression: String) -> void:
	"""計算數學表達式"""
	print("🔢 計算表達式: %s" % expression)
	
	var http = _create_http_request("calculate")
	http.request_completed.connect(_on_calculate_completed)
	http.timeout = 10.0
	
	var payload = {"expression": expression}
	
	var headers = ["Content-Type: application/json"]
	var error = http.request(
		PYTHON_API_BASE + "/calculate",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	
	if error != OK:
		push_warning("❌ 計算請求失敗: %d" % error)
		api_error.emit("calculate", "請求發送失敗")

func _on_calculate_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_cleanup_http_request("calculate")
	
	if code == 200:
		var response = _parse_json_response(body)
		if response.get("success", false):
			var calc_result = response.get("result", "")
			print("✅ 計算結果: %s" % calc_result)
			calculate_result_received.emit(calc_result)
		else:
			var error_msg = response.get("error", "計算失敗")
			print("❌ 計算失敗: %s" % error_msg)
			api_error.emit("calculate", error_msg)
	else:
		print("❌ 計算請求失敗 (Code: %d)" % code)
		api_error.emit("calculate", "HTTP錯誤: %d" % code)

func open_system_calculator() -> void:
	"""打開系統計算器"""
	print("🖩 正在打開系統計算器...")
	
	var http = _create_http_request("open_calc")
	http.request_completed.connect(_on_open_calculator_completed)
	
	var headers = ["Content-Type: application/json"]
	var error = http.request(
		PYTHON_API_BASE + "/open_calculator",
		headers,
		HTTPClient.METHOD_POST,
		"{}"
	)
	
	if error != OK:
		push_warning("❌ 打開計算器請求失敗: %d" % error)
		api_error.emit("open_calc", "請求發送失敗")

func _on_open_calculator_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_cleanup_http_request("open_calc")
	
	if code == 200:
		var response = _parse_json_response(body)
		if response.get("success", false):
			print("✅ 系統計算器已打開")
			calculator_opened.emit()
		else:
			print("❌ 打開計算器失敗: %s" % response.get("error", "未知錯誤"))
			api_error.emit("open_calc", response.get("error", "未知錯誤"))
	else:
		print("❌ 打開計算器請求失敗 (Code: %d)" % code)
		api_error.emit("open_calc", "HTTP錯誤: %d" % code)

# ===== 工具函數 =====

func _parse_json_response(body: PackedByteArray) -> Dictionary:
	"""解析JSON響應"""
	var response_text = body.get_string_from_utf8()
	var json = JSON.new()
	
	if json.parse(response_text) == OK:
		return json.data
	else:
		push_warning("JSON解析失敗: %s" % response_text)
		return {}

# ===== 調試功能 =====

func print_status() -> void:
	"""打印API客戶端狀態"""
	print("\n=== 🐍 Python API客戶端狀態 ===")
	print("服務器地址: %s" % PYTHON_API_BASE)
	print("活躍請求數: %d" % http_requests.size())
	print("================================\n")
