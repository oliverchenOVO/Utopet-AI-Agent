# llm_api_manager_ollama.gd - 使用Ollama的LLM API管理器
extends Node

# ===== Ollama API配置 =====
const OLLAMA_URL = "http://127.0.0.1:11434"
const API_ENDPOINT = "/api/chat"
const MODEL_NAME = "qwen3.5:9b-q4_K_M"

# ===== HTTP请求组件 =====
var http_request: HTTPRequest
var is_request_in_progress = false

# ===== 回调信号 =====
signal conversation_response_received(response_text: String)
signal api_error_occurred(error_message: String)

# ===== 对话状态 =====
var conversation_history: Array = []
var max_conversation_turns = 10
var _current_name1: String = "角色A"
var _current_name2: String = "角色B"

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)
	http_request.timeout = 120.0  # 9B 模型冷啟動需要更長時間
	
	print("🤖 Ollama LLM API管理器初始化完成")
	print("📡 服务器地址: %s" % OLLAMA_URL)
	print("🧠 模型: %s" % MODEL_NAME)

# ===== 核心API调用函数 =====

func send_agent_conversation_request(agent1_data: Dictionary, agent2_data: Dictionary) -> void:
	"""发送Agent对话请求到Ollama"""
	if is_request_in_progress:
		print("⚠️ API请求正在进行中，请稍候...")
		return

	_current_name1 = agent1_data.get("name", "角色A")
	_current_name2 = agent2_data.get("name", "角色B")

	# 构建对话prompt
	var messages = _build_chat_messages(agent1_data, agent2_data)
	
	# 构建Ollama API请求payload
	# think: false 關閉 Qwen3 系列的思考模式，避免輸出 <think>...</think> 干擾解析
	var payload = {
		"model": MODEL_NAME,
		"messages": messages,
		"stream": false,
		"think": false,
		"options": {
			"temperature": 0.7,
			"num_predict": 300
		}
	}
	
	# 发送HTTP请求
	_send_http_request(payload)

func _build_chat_messages(agent1_data: Dictionary, agent2_data: Dictionary) -> Array:
	"""构建Chat格式的消息，使用實際 Agent 名稱與職業"""
	var name1 = agent1_data.get("name", "角色A")
	var name2 = agent2_data.get("name", "角色B")
	var role1 = _get_role_description(name1)
	var role2 = _get_role_description(name2)

	var memory_context = agent1_data.get("memory_context", "")

	var system_content = """你是一個對話生成AI。請為兩個NPC角色生成一段繁體中文對話。
場景：小鎮中，兩人在移動途中偶遇停下交談。
要求：
1. 必須使用正統「繁體中文」，語氣口語自然，每句約 10-20 字。
2. 兩人互相回應，各說 2 句，共 4 句。
3. 若有歷史記憶，對話可自然帶入過去的互動（不要生硬引用）。
4. 嚴格按照以下格式輸出（使用全形冒號）：
%s：(內容)
%s：(內容)
%s：(內容)
%s：(內容)""" % [name1, name2, name1, name2]

	var memory_section = ""
	if memory_context != "":
		memory_section = "\n\n【過去互動記憶，可自然融入對話】\n" + memory_context

	var rel = agent1_data.get("relationship", {})
	var rel_section = ""
	if rel.size() > 0:
		var trust     = float(rel.get("trust", 50.0))
		var affection = float(rel.get("affection", 50.0))
		var state     = str(rel.get("social_state", "Normal"))
		var rel_desc: String
		if state == "Cold_War":
			rel_desc = "目前關係緊張、冷戰中"
		elif trust > 70 and affection > 70:
			rel_desc = "關係融洽，彼此信任"
		elif trust < 30 or affection < 30:
			rel_desc = "關係疏離，互有戒心"
		else:
			rel_desc = "關係普通"
		rel_section = "\n【兩人目前關係：%s（信任%.0f/100，好感%.0f/100）】" % [rel_desc, trust, affection]

	var user_content = """請生成對話：
%s：%s，心情%s。
%s：%s，心情%s。
主題：工作近況 / 天氣 / 日常閒聊%s%s""" % [
		name1, role1, _translate_mood(agent1_data.get("mood", "neutral")),
		name2, role2, _translate_mood(agent2_data.get("mood", "neutral")),
		memory_section, rel_section
	]

	return [
		{"role": "system", "content": system_content},
		{"role": "user", "content": user_content}
	]

func _get_role_description(name: String) -> String:
	"""依 Agent 名稱回傳職業描述"""
	match name:
		"Jack": return "伐木工，整天在樹林裡工作"
		"Mike": return "礦工，負責開採礦石"
		"Fin":  return "釣魚人，喜歡在溪邊垂釣"
		"Buba": return "農夫，照顧農作物和動物"
		_: return "小鎮居民"

func _translate_mood(mood: String) -> String:
	"""将英文心情翻译为中文"""
	match mood:
		"organized": return "井然有序"
		"refreshed": return "神清气爽"
		"happy": return "开心"
		"busy": return "忙碌"
		"satisfied": return "满足"
		"peaceful": return "平静"
		"energetic": return "精力充沛"
		_: return "平常"

func _send_http_request(payload: Dictionary) -> void:
	"""发送HTTP请求到Ollama"""
	is_request_in_progress = true
	
	var full_url = OLLAMA_URL + API_ENDPOINT
	var headers = [
		"Content-Type: application/json"
	]
	
	var json_payload = JSON.stringify(payload)
	
	print("🚀 发送对话请求到Ollama...")
	print("📡 URL: %s" % full_url)
	print("🧠 模型: %s" % MODEL_NAME)
	
	var error = http_request.request(
		full_url,
		headers,
		HTTPClient.METHOD_POST,
		json_payload
	)
	
	if error != OK:
		_handle_request_error("HTTP请求发送失败: %d" % error)

# ===== HTTP响应处理 =====

func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""处理HTTP请求完成"""
	is_request_in_progress = false
	
	print("📨 收到API响应 - Code: %d, Result: %d" % [response_code, result])
	
	if response_code == 200:
		_handle_successful_response(body)
	else:
		_handle_error_response(response_code, body, result)

func _handle_successful_response(body: PackedByteArray) -> void:
	"""处理成功的API响应"""
	var response_text = body.get_string_from_utf8()
	
	var json = JSON.new()
	var parse_result = json.parse(response_text)
	
	if parse_result != OK:
		_handle_request_error("JSON解析失败")
		return
	
	var response_data = json.data
	
	# Ollama 返回格式: {"response": "...", "done": true, ...}
	if response_data.has("message") and response_data["message"].has("content"):
		var generated_text = response_data["message"]["content"]
		
		print("✅ 对话生成成功!")
		print("💬 内容长度: %d字符" % generated_text.length())
		
		if generated_text.strip_edges() == "":
			print("⚠️ 检测到空响应，使用备用对话")
			generated_text = _generate_fallback_dialogue()
		
		var cleaned_dialogue = _clean_dialogue_text(generated_text)
		print("📝 生成的对话: %s" % cleaned_dialogue.substr(0, 100))
		
		conversation_response_received.emit(cleaned_dialogue)
	
	# 兼容舊格式或錯誤處理
	elif response_data.has("response"): # 這是 /api/generate 的格式，留著以防萬一
		var generated_text = response_data.response
		conversation_response_received.emit(_clean_dialogue_text(generated_text))
		
	else:
		_handle_request_error("API响应格式错误：未找到message.content字段")

func _generate_fallback_dialogue() -> String:
	"""生成備用對話，使用當前對話雙方的實際名稱"""
	var n1 = _current_name1
	var n2 = _current_name2
	var fallback_dialogues = [
		"%s：今天天氣真不錯呢！\n%s：是啊，很適合出來走走。\n%s：工作完出來散步真舒服。\n%s：是啊，難得休息一下。" % [n1, n2, n1, n2],
		"%s：嘿，你也在這裡？\n%s：剛剛忙完，出來透透氣。\n%s：今天辛苦了。\n%s：你也是，要保重啊。" % [n1, n2, n1, n2],
		"%s：在這遇到你真巧！\n%s：是啊，今天天氣真好。\n%s：偶爾放鬆很重要。\n%s：說得對，走，一起去看看。" % [n1, n2, n1, n2],
	]
	return fallback_dialogues[randi() % fallback_dialogues.size()]

func _handle_error_response(response_code: int, body: PackedByteArray, result: int) -> void:
	"""处理错误响应"""
	var error_text = body.get_string_from_utf8()
	var error_message = ""
	
	if response_code == 0:
		# 连接失败
		error_message = "无法连接到Ollama服务器 (端口 11434)"
		print("❌ %s" % error_message)
		print("🔧 请检查：")
		print("   1. Ollama是否正在运行 (运行 'ollama serve')")
		print("   2. 模型是否已下载 (运行 'ollama pull %s')" % MODEL_NAME)
	else:
		error_message = "API请求失败 (Code: %d)" % response_code
		print("❌ %s" % error_message)
		print("📄 响应: %s" % error_text)
	
	_handle_request_error(error_message)

func _handle_request_error(error_message: String) -> void:
	"""处理请求错误"""
	print("❌ LLM API错误: %s" % error_message)
	
	print("🔄 使用备用对话内容")
	var fallback = _generate_fallback_dialogue()
	conversation_response_received.emit(fallback)

# ===== 对话文本处理 =====

func _clean_dialogue_text(raw_text: String) -> String:
	"""清理和格式化对话文本"""
	var cleaned = raw_text.strip_edges()
	
	# 移除多余的换行符
	cleaned = cleaned.replace("\n\n\n", "\n")
	cleaned = cleaned.replace("\n\n", "\n")
	
	# 如果文本不包含已知角色名，嘗試補上名稱
	if not (cleaned.contains(_current_name1) or cleaned.contains(_current_name2)):
		var lines = cleaned.split("\n")
		var formatted_lines = []
		for i in range(lines.size()):
			var line = lines[i].strip_edges()
			if line != "":
				var speaker = _current_name1 if i % 2 == 0 else _current_name2
				if not line.begins_with(speaker):
					line = speaker + "：" + line
				formatted_lines.append(line)
		cleaned = "\n".join(formatted_lines)
	
	return cleaned

# ===== 实用工具函数 =====

func test_connection() -> void:
	"""测试与Ollama的连接"""
	print("🔍 测试Ollama连接...")
	
	var test_payload = {
		"model": MODEL_NAME,
		"prompt": "請說：你好",
		"stream": false,
		"options": {
			"num_predict": 50
		}
	}
	
	_send_http_request(test_payload)

func clear_conversation_history() -> void:
	"""清除对话历史"""
	conversation_history.clear()
	print("🧹 对话历史已清除")

func get_conversation_status() -> Dictionary:
	"""获取当前对话状态"""
	return {
		"is_busy": is_request_in_progress,
		"history_length": conversation_history.size(),
		"server_url": OLLAMA_URL,
		"model_name": MODEL_NAME
	}

func print_debug_info() -> void:
	"""打印调试信息"""
	print("\n=== 🤖 Ollama LLM API管理器状态 ===")
	print("服务器: %s" % OLLAMA_URL)
	print("模型: %s" % MODEL_NAME)
	print("请求进行中: %s" % ("是" if is_request_in_progress else "否"))
	print("对话历史长度: %d" % conversation_history.size())
	print("============================\n")
