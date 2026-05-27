# agent_conversation_manager.gd - 動態聊天框對話系統
extends Node

# ===== 信號 =====
signal conversation_started(agent1_name: String, agent2_name: String)
signal conversation_ended()
signal dialogue_line_displayed(speaker: String, text: String)

# ===== 節點引用 =====
var llm_api_manager: Node
var world_script: Node
var agent1: Node
var agent2: Node

# ===== 記憶系統 HTTP =====
const MEMORY_API = "http://127.0.0.1:8000/memory"
const SOCIAL_API = "http://127.0.0.1:8000/social"
var _mem_http: HTTPRequest           # 記憶儲存（fire-and-forget）
var _ctx_http: HTTPRequest           # 記憶 context 載入（需等回應）
var _social_check_http: HTTPRequest  # 社交引擎決策（需等回應）
var _rel_http: HTTPRequest           # 關係值查詢（需等回應）
var _awaiting_social_check: bool = false
var _social_check_pair: Array = []
var _agents_registered: bool = false
var _last_social_tick_min: int = -1
var _pending_memory_context: String = ""
var _pending_relationship: Dictionary = {}
var _pending_preload_count: int = 0

# ===== 對話狀態 =====
var is_conversation_active = false
var current_dialogue_lines: Array = []
# 每對 Agent 各自的冷卻時間（真實秒數），不同配對互不干擾
var pair_cooldowns: Dictionary = {}
const PAIR_COOLDOWN_SEC = 60.0
var current_line_index = 0
var is_displaying_line = false
var line_display_timer = 0.0
var line_display_duration = 5.0

# ===== 相遇觸發設定 =====
const TRIGGER_DISTANCE = 35.0   # 兩 Agent 距離小於此值觸發對話
const AGENT_NAMES = ["Jack", "Mike", "Fin", "Buba"]

# 每個 Agent 的泡泡邊框顏色
const AGENT_COLORS = {
	"Jack": Color(0.9, 0.5, 0.1, 1.0),   # 橘（伐木工）
	"Mike": Color(0.6, 0.6, 0.7, 1.0),   # 灰（礦工）
	"Fin":  Color(0.2, 0.6, 0.9, 1.0),   # 藍（釣魚人）
	"Buba": Color(0.2, 0.7, 0.3, 1.0),   # 綠（農夫）
}

const AGENT_PROFILES = {
	"Jack": {"extroversion": 0.6, "agreeableness": 0.7, "core_principles": ["animal_abuse"]},
	"Mike": {"extroversion": 0.4, "agreeableness": 0.5, "core_principles": ["malicious_deception"]},
	"Fin":  {"extroversion": 0.5, "agreeableness": 0.8, "core_principles": []},
	"Buba": {"extroversion": 0.7, "agreeableness": 0.9, "core_principles": ["animal_abuse"]},
}

var agents: Array = []                      # 世界中所有 agent 節點
var current_speaker_names: Array = ["", ""] # [agent1 名, agent2 名]

# ===== 對話泡泡組件 =====
var _bubble_layer: CanvasLayer   # 獨立 CanvasLayer：座標系 = Viewport 像素，與 canvas_t 一致
var agent1_bubble: Control
var agent2_bubble: Control

# ===== 顏色配置 =====
const SHOPKEEPER_BORDER_COLOR = Color(0.9, 0.5, 0.1, 1.0)   # 橘色
const RESIDENT_BORDER_COLOR = Color(0.15, 0.45, 0.15, 1.0)  # 深綠色
const BUBBLE_BG_COLOR = Color(0.95, 0.95, 0.88, 0.95)       # 淺米色

# ===== 泡泡尺寸配置（根據 zoom 動態計算，見 create_dynamic_bubble）=====
# zoom = canvas_t.get_scale().x = int_scale × camera_zoom
# 預設縮放(zoom≈1)：泡泡 58-92px；最近縮放(zoom=8)：114-176px
const BUBBLE_OFFSET_Y = 55   # 已棄用，實際偏移由 _update_bubble_positions 動態公式計算

# ===== 歷史記錄 =====
var history_ui: Control
var history_scroll: ScrollContainer
var history_content: VBoxContainer
var history_visible = false
var conversation_history: Array = []

func _ready() -> void:
	print("💬 動態聊天框對話系統初始化...")

	await get_tree().process_frame

	# 建立記憶系統的 HTTP 節點
	_mem_http = HTTPRequest.new()
	_ctx_http = HTTPRequest.new()
	_ctx_http.request_completed.connect(_on_memory_context_received)
	_social_check_http = HTTPRequest.new()
	_social_check_http.request_completed.connect(_on_social_check_received)
	_rel_http = HTTPRequest.new()
	_rel_http.request_completed.connect(_on_relationship_received)
	add_child(_mem_http)
	add_child(_ctx_http)
	add_child(_social_check_http)
	add_child(_rel_http)

	setup_llm_api_manager()
	setup_dialogue_bubbles()
	setup_history_ui()

	print("✅ 對話系統就緒")

# ===== 初始化 =====

func setup_llm_api_manager() -> void:
	var llm_script = load("res://llm_api_manager_optimized.gd")
	if not llm_script:
		llm_script = load("res://llm_api_manager.gd")
	
	if llm_script:
		llm_api_manager = llm_script.new()
		llm_api_manager.name = "LLM_API_Manager"
		add_child(llm_api_manager)
		
		if llm_api_manager.has_signal("conversation_response_received"):
			llm_api_manager.conversation_response_received.connect(_on_conversation_response_received)
		if llm_api_manager.has_signal("api_error_occurred"):
			llm_api_manager.api_error_occurred.connect(_on_api_error_occurred)
		
		print("🤖 LLM管理器已連接")

func setup_dialogue_bubbles() -> void:
	"""創建對話泡泡容器（掛在 CanvasLayer，座標系與 canvas_transform 吻合）"""
	_bubble_layer = CanvasLayer.new()
	_bubble_layer.name       = "BubbleLayer"
	_bubble_layer.layer      = 50   # 高於遊戲世界，低於 UI 面板（layer 20-22）
	_bubble_layer.follow_viewport_enabled = false
	add_child(_bubble_layer)

	agent1_bubble = Control.new()
	agent1_bubble.name    = "Agent1Bubble"
	agent1_bubble.z_index = 10
	agent1_bubble.visible = false

	agent2_bubble = Control.new()
	agent2_bubble.name    = "Agent2Bubble"
	agent2_bubble.z_index = 10
	agent2_bubble.visible = false

	_bubble_layer.add_child(agent1_bubble)
	_bubble_layer.add_child(agent2_bubble)

	print("💭 對話泡泡創建完成（CanvasLayer layer=50）")

func create_dynamic_bubble(bubble_container: Control, text: String, speaker_name: String) -> void:
	"""創建動態尺寸的聊天框（尺寸隨相機縮放即時調整）"""
	# ── 依目前縮放量動態計算所有尺寸 ──
	# zoom = int_scale × camera_zoom；預設 zoom≈1（縮到全圖），最大 zoom=8（最近）
	# zoom = int_scale × camera_zoom
	# agent sprite = 16 world unit → 16 * zoom screen px
	# 目標比例：bubble_max_w ≈ 3× agent 高度，讓泡泡視覺上不超過角色 3 倍寬
	var zoom   := get_viewport().get_canvas_transform().get_scale().x
	var pad    := maxf(1.0, zoom * 0.5)             # 內邊距（縮半）1–4 px
	var min_w  := 30.0 + 9.0  * zoom               # 最小寬（拉寬）39–102 px
	var max_w  := 55.0 + 16.0 * zoom               # 最大寬（拉寬）71–183 px
	var font_s := clampi(int(zoom * 0.8 + 4.5), 6, 9)   # 字型（縮半）6–9 px
	var border := maxi(1, int(zoom * 0.4))          # 邊框 1–3 px
	var corner := maxi(1, int(zoom * 0.9))          # 圓角 1–7 px

	# 清除舊內容
	for child in bubble_container.get_children():
		child.queue_free()

	# 面板
	var panel = PanelContainer.new()
	bubble_container.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = BUBBLE_BG_COLOR
	style.border_color = AGENT_COLORS.get(speaker_name, RESIDENT_BORDER_COLOR)
	style.set_border_width_all(border)
	style.set_corner_radius_all(corner)
	style.corner_radius_bottom_right = maxi(1, corner / 3)   # 小尾巴
	style.content_margin_left   = pad
	style.content_margin_right  = pad
	style.content_margin_top    = pad
	style.content_margin_bottom = pad
	panel.add_theme_stylebox_override("panel", style)

	# 文字標籤
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_s)
	label.add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = max_w - pad * 2
	panel.add_child(label)

	await get_tree().process_frame

	# 計算動態寬高
	var text_size  := label.get_minimum_size()
	var bubble_width := clampf(text_size.x + pad * 2, min_w, max_w)

	if text_size.x + pad * 2 > max_w:
		label.custom_minimum_size.x = max_w - pad * 2
		await get_tree().process_frame
		text_size = label.get_minimum_size()
		bubble_width = max_w

	var bubble_height := text_size.y + pad * 2

	panel.custom_minimum_size = Vector2(bubble_width, bubble_height)
	panel.size     = Vector2(bubble_width, bubble_height)
	# X 置中；Y 往上偏移自身高度（底邊貼容器原點，頭頂偏移由 _update_bubble_positions 控制）
	panel.position = Vector2(-bubble_width / 2.0, -bubble_height)

func setup_history_ui() -> void:
	"""設置歷史記錄UI"""
	history_ui = Control.new()
	history_ui.visible = false
	history_ui.z_index = 200
	
	var panel = Panel.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(300, 200)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.85)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	history_ui.add_child(panel)
	
	var title = Label.new()
	title.text = "📜 對話歷史 (F6關閉)"
	title.position = Vector2(10, 5)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(title)
	
	history_scroll = ScrollContainer.new()
	history_scroll.position = Vector2(5, 25)
	history_scroll.size = Vector2(290, 170)
	panel.add_child(history_scroll)
	
	history_content = VBoxContainer.new()
	history_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_scroll.add_child(history_content)
	
	get_tree().root.add_child(history_ui)

# ===== 主循環 =====

func _process(delta: float) -> void:
	if agents.is_empty():
		_find_agents()

	if not is_conversation_active:
		_check_proximity_meeting()
	else:
		_update_bubble_positions()
		_process_dialogue_display(delta)

	# 每模擬分鐘同步社交引擎（tick + 每 5 分鐘更新生理值）
	var world = get_parent()
	if world and "sim_clock_minutes" in world:
		var cur_min: int = world.sim_clock_minutes
		if cur_min != _last_social_tick_min:
			_last_social_tick_min = cur_min
			_social_tick(1.0)
			if cur_min % 5 == 0 and _agents_registered:
				_update_physio_all()

func _find_agents() -> void:
	"""從父節點（world）找到所有 Agent"""
	var world = get_parent()
	if not world:
		return
	agents.clear()
	for aname in AGENT_NAMES:
		if world.has_node(aname):
			agents.append(world.get_node(aname))
	if agents.size() > 0:
		print("💬 [對話系統] 找到 %d 個 Agent: %s" % [agents.size(), AGENT_NAMES.filter(func(n): return get_parent().has_node(n))])
		if not _agents_registered:
			_register_agents_social()

func _get_pair_key(a: Node, b: Node) -> String:
	"""產生配對 key，與順序無關（Jack_Buba == Buba_Jack）"""
	var na = a.get("agent_name") if "agent_name" in a else a.name
	var nb = b.get("agent_name") if "agent_name" in b else b.name
	return (na + "_" + nb) if na < nb else (nb + "_" + na)

func evaluate_interaction_priority(initiator: Node, target: Node) -> Dictionary:
	"""純數值計算，判斷兩個 Agent 是否應該開啟對話"""
	var fatigue_i = initiator.get("fatigue") if "fatigue" in initiator else 0.0
	var hunger_i  = initiator.get("hunger")  if "hunger"  in initiator else 0.0
	var mood_i    = initiator.get("mood_value") if "mood_value" in initiator else 70.0

	# 疲憊超過 90 才直接拒絕（原 85，配合降速後較少達到）
	if fatigue_i >= 90.0:
		return {"should_interact": false, "reason": "太疲憊了"}

	# V_schedule：極度飢餓才拒絕（hunger > 65 才有壓力）；疲憊壓力降低
	var hunger_pressure  = max(0.0, hunger_i - 65.0) * 0.4   # 原 (hunger-60)*0.5
	var fatigue_pressure = fatigue_i * 0.20                    # 原 0.3
	var v_schedule       = 35.0 + hunger_pressure + fatigue_pressure  # 原 baseline 40

	# V_social：心情拉動意願，疲憊懲罰降低
	var v_social = 50.0 * (mood_i / 100.0) - fatigue_i * 0.15  # 原 fatigue*0.25

	# 門檻從 0.55 降到 0.50，讓正常狀態更容易通過
	var should_interact = v_social > v_schedule * 0.50
	return {
		"should_interact": should_interact,
		"v_social":   v_social,
		"v_schedule": v_schedule,
		"reason":     "OK" if should_interact else ("餓" if hunger_i > 80 else "疲憊優先")
	}

func _check_proximity_meeting() -> void:
	"""任意兩個 Agent 距離小於 TRIGGER_DISTANCE 時觸發對話（每對各自冷卻）"""
	if is_conversation_active or agents.size() < 2 or _awaiting_social_check:
		return
	var now = Time.get_ticks_msec() / 1000.0
	for i in range(agents.size()):
		for j in range(i + 1, agents.size()):
			var a = agents[i]
			var b = agents[j]
			var key = _get_pair_key(a, b)
			if pair_cooldowns.get(key, 0.0) > now:
				continue
			if a.global_position.distance_to(b.global_position) < TRIGGER_DISTANCE:
				# 本地快速預篩（疲憊 > 85 直接跳過，不耗 HTTP）
				var eval = evaluate_interaction_priority(a, b)
				if not eval["should_interact"]:
					print("🚫 [%s↔%s] 跳過對話：%s" % [
						a.get("agent_name") if "agent_name" in a else a.name,
						b.get("agent_name") if "agent_name" in b else b.name,
						eval["reason"]])
					pair_cooldowns[key] = now + 10.0
					continue
				# 呼叫社交引擎做關係值決策（非同步）
				_awaiting_social_check = true
				_social_check_pair = [a, b]
				pair_cooldowns[key] = now + 5.0  # 等待期間防重複觸發
				var na = a.get("agent_name") if "agent_name" in a else a.name
				var nb = b.get("agent_name") if "agent_name" in b else b.name
				var world = get_parent()
				var sim_min = world.sim_clock_minutes if world and "sim_clock_minutes" in world else 0
				var check_body = JSON.stringify({
					"initiator_id": na,
					"target_id":    nb,
					"distance":     a.global_position.distance_to(b.global_position),
					"sim_minutes":  float(sim_min)
				})
				if _social_check_http.request(SOCIAL_API + "/check",
						["Content-Type: application/json"], HTTPClient.METHOD_POST, check_body) != OK:
					# 社交 API 不可用，退回本地決策
					_awaiting_social_check = false
					agent1 = a
					agent2 = b
					_start_conversation()
				return

func _start_conversation() -> void:
	"""開始對話"""
	is_conversation_active = true

	var name1 = agent1.get("agent_name") if "agent_name" in agent1 else agent1.name
	var name2 = agent2.get("agent_name") if "agent_name" in agent2 else agent2.name
	current_speaker_names = [name1, name2]

	# 暫停排程 + 停止移動，兩人都駐足不會再被 tick_schedule 驅動離開
	agent1.paused_for_conversation = true
	agent2.paused_for_conversation = true
	if agent1.has_method("stop_movement"):
		agent1.stop_movement()
	if agent2.has_method("stop_movement"):
		agent2.stop_movement()

	print("🎉 %s 與 %s 相遇！開始對話..." % [name1, name2])
	conversation_started.emit(name1, name2)

	# 並行預載：記憶 context + 關係值，兩者都到齊後再發 LLM 請求
	_pending_memory_context = ""
	_pending_relationship = {}
	_pending_preload_count = 0

	var mem_body = JSON.stringify({"agent1": name1, "agent2": name2})
	if _ctx_http.request(MEMORY_API + "/context",
			["Content-Type: application/json"], HTTPClient.METHOD_POST, mem_body) == OK:
		_pending_preload_count += 1

	var rel_url = SOCIAL_API + "/relationship/%s/%s" % [name1, name2]
	if _rel_http.request(rel_url, [], HTTPClient.METHOD_GET, "") == OK:
		_pending_preload_count += 1

	if _pending_preload_count == 0:
		_maybe_send_llm()

func _on_memory_context_received(_result, _code, _headers, body: PackedByteArray) -> void:
	"""收到記憶 context，再發送 LLM 請求"""
	var text = body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(text) == OK and json.data.has("context"):
		_pending_memory_context = json.data["context"]
		if _pending_memory_context != "":
			print("🧠 [記憶] 載入歷史記憶，注入 LLM prompt")
	_pending_preload_count -= 1
	_maybe_send_llm()

func _send_llm_request(a1_data: Dictionary, a2_data: Dictionary) -> void:
	if llm_api_manager:
		llm_api_manager.send_agent_conversation_request(a1_data, a2_data)
	else:
		_use_fallback_dialogue()

func _maybe_send_llm() -> void:
	"""計數歸零時才發 LLM 請求（確保記憶 + 關係值都已到位）"""
	if _pending_preload_count > 0:
		return
	var name1 = current_speaker_names[0]
	var name2 = current_speaker_names[1]
	var a1_data = {
		"name": name1,
		"mood": agent1.get("mood") if agent1 and "mood" in agent1 else "neutral",
		"memory_context": _pending_memory_context,
		"relationship": _pending_relationship
	}
	var a2_data = {
		"name": name2,
		"mood": agent2.get("mood") if agent2 and "mood" in agent2 else "neutral"
	}
	_send_llm_request(a1_data, a2_data)

func _on_relationship_received(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	"""收到關係值，存起來供 LLM 使用"""
	if code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			_pending_relationship = json.data
			print("💞 [社交] 關係值：trust=%.1f affection=%.1f state=%s" % [
				_pending_relationship.get("trust", 50.0),
				_pending_relationship.get("affection", 50.0),
				_pending_relationship.get("social_state", "Normal")
			])
	_pending_preload_count -= 1
	_maybe_send_llm()

func _on_social_check_received(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	"""社交引擎決策回調：根據 action 決定是否開啟對話"""
	_awaiting_social_check = false
	if _social_check_pair.size() < 2:
		return
	var a: Node = _social_check_pair[0]
	var b: Node = _social_check_pair[1]
	_social_check_pair = []
	var key = _get_pair_key(a, b)
	var now = Time.get_ticks_msec() / 1000.0
	var na = a.get("agent_name") if "agent_name" in a else a.name
	var nb = b.get("agent_name") if "agent_name" in b else b.name

	if code != 200:
		print("⚠️ [社交] /check 失敗 (code=%d)，退回本地決策" % code)
		agent1 = a
		agent2 = b
		_start_conversation()
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		agent1 = a
		agent2 = b
		_start_conversation()
		return

	var action: String = json.data.get("action", "skip")
	match action:
		"accept_invitation", "greet_no_interrupt":
			print("✅ [社交] %s↔%s 社交引擎批准（action=%s）" % [na, nb, action])
			agent1 = a
			agent2 = b
			_start_conversation()
		"decline_gracefully":
			print("🤝 [社交] %s 婉拒了 %s 的邀約" % [nb, na])
			pair_cooldowns[key] = now + PAIR_COOLDOWN_SEC
		_:
			print("🚫 [社交] %s↔%s 跳過（action=%s，reason=%s）" % [
				na, nb, action, json.data.get("reason", "")])
			pair_cooldowns[key] = now + PAIR_COOLDOWN_SEC

func _register_agents_social() -> void:
	"""啟動時將所有 Agent 人格登錄進 Python 社交引擎"""
	_agents_registered = true
	for agent in agents:
		var name = agent.get("agent_name") if "agent_name" in agent else agent.name
		var prof = AGENT_PROFILES.get(name, {"extroversion": 0.5, "agreeableness": 0.6, "core_principles": []})
		var hunger  = (agent.get("hunger")  if "hunger"  in agent else 30.0) / 100.0
		var fatigue = (agent.get("fatigue") if "fatigue" in agent else 30.0) / 100.0
		var http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(func(_r,_c,_h,_b): http.queue_free())
		http.request(SOCIAL_API + "/register", ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify({
				"agent_id":        name,
				"extroversion":    prof["extroversion"],
				"agreeableness":   prof["agreeableness"],
				"core_principles": prof["core_principles"],
				"hunger":          hunger,
				"fatigue":         fatigue
			}))
	print("🤝 [社交] 所有 Agent 已向社交引擎登錄")

func _social_tick(elapsed: float) -> void:
	"""每模擬分鐘通知社交引擎更新冷戰計時器"""
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_r,_c,_h,_b): http.queue_free())
	http.request(SOCIAL_API + "/tick", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify({"sim_minutes_elapsed": elapsed}))

func _update_physio_all() -> void:
	"""每 5 模擬分鐘同步各 Agent 生理值到社交引擎"""
	for agent in agents:
		var name    = agent.get("agent_name") if "agent_name" in agent else agent.name
		var hunger  = (agent.get("hunger")  if "hunger"  in agent else 30.0) / 100.0
		var fatigue = (agent.get("fatigue") if "fatigue" in agent else 30.0) / 100.0
		var http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(func(_r,_c,_h,_b): http.queue_free())
		http.request(SOCIAL_API + "/physio", ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify({
				"agent_id": name,
				"hunger":   hunger,
				"fatigue":  fatigue
			}))

func _on_conversation_response_received(response_text: String) -> void:
	"""收到LLM回應"""
	print("📨 收到對話回應")
	current_dialogue_lines = _parse_dialogue(response_text)
	current_line_index = 0
	
	if current_dialogue_lines.size() > 0:
		_display_current_line()
	else:
		_use_fallback_dialogue()

func _on_api_error_occurred(error_msg: String) -> void:
	print("❌ API錯誤: %s" % error_msg)
	_use_fallback_dialogue()

func _use_fallback_dialogue() -> void:
	"""使用備用對話"""
	var n1 = current_speaker_names[0] if current_speaker_names[0] != "" else "Jack"
	var n2 = current_speaker_names[1] if current_speaker_names[1] != "" else "Mike"
	current_dialogue_lines = [
		{"speaker": n1, "content": "嘿，今天天氣還不錯呢。"},
		{"speaker": n2, "content": "是啊，正好趁空檔出來走走。"},
		{"speaker": n1, "content": "最近工作怎麼樣？"},
		{"speaker": n2, "content": "忙是忙，但挺充實的。"}
	]
	current_line_index = 0
	_display_current_line()

func _parse_dialogue(text: String) -> Array:
	"""解析對話文本，依據當前對話雙方名稱辨識發言者"""
	var lines = []
	var name1 = current_speaker_names[0]
	var name2 = current_speaker_names[1]

	for raw_line in text.split("\n"):
		var line = raw_line.strip_edges()
		if line == "":
			continue

		var speaker = ""
		if name1 != "" and line.begins_with(name1):
			speaker = name1
		elif name2 != "" and line.begins_with(name2):
			speaker = name2

		if speaker != "":
			var colon_pos = line.find("：")
			if colon_pos == -1:
				colon_pos = line.find(":")
			if colon_pos != -1:
				var content = line.substr(colon_pos + 1).strip_edges()
				if content != "":
					lines.append({"speaker": speaker, "content": content})

	return lines

func _display_current_line() -> void:
	"""顯示當前對話行"""
	if current_line_index >= current_dialogue_lines.size():
		_end_conversation()
		return
	
	var line = current_dialogue_lines[current_line_index]
	var speaker = line["speaker"]
	var content = line["content"]
	var is_agent1 = (speaker == current_speaker_names[0])

	# 隱藏所有泡泡
	agent1_bubble.visible = false
	agent2_bubble.visible = false

	# 選擇對應的泡泡
	var bubble = agent1_bubble if is_agent1 else agent2_bubble

	# 創建動態聊天框
	create_dynamic_bubble(bubble, content, speaker)
	bubble.visible = true
	
	# 更新位置
	_update_bubble_positions()
	
	# 添加到歷史
	_add_to_history(speaker, content)
	
	is_displaying_line = true
	line_display_timer = 0.0
	
	dialogue_line_displayed.emit(speaker, content)
	print("💬 [%s]: %s" % [speaker, content])

func _process_dialogue_display(delta: float) -> void:
	"""處理對話顯示計時"""
	if not is_displaying_line:
		return
	
	line_display_timer += delta
	
	if line_display_timer >= line_display_duration:
		is_displaying_line = false
		current_line_index += 1
		
		# 短暫延遲後顯示下一行
		await get_tree().create_timer(0.8).timeout
		_display_current_line()

func _update_bubble_positions() -> void:
	"""更新泡泡位置跟隨 Agent（Viewport 座標系，每幀呼叫以支援相機縮放/平移）"""
	var canvas_t = get_viewport().get_canvas_transform()
	# 依相機 zoom 動態計算頭頂偏移（sprite 約 16 world unit 高）
	var zoom       = canvas_t.get_scale().x
	var head_offset = 16.0 * zoom + 6.0   # sprite 高度（viewport px）+ 6px 間距
	if agent1 and agent1_bubble.visible:
		var vp_pos = canvas_t * agent1.global_position
		agent1_bubble.position = Vector2(vp_pos.x, vp_pos.y - head_offset)
	if agent2 and agent2_bubble.visible:
		var vp_pos = canvas_t * agent2.global_position
		agent2_bubble.position = Vector2(vp_pos.x, vp_pos.y - head_offset)

func _end_conversation() -> void:
	"""結束對話，儲存記憶，設定冷卻"""
	print("🎬 對話結束")

	agent1_bubble.visible = false
	agent2_bubble.visible = false

	# 對話結束後給雙方 +8 心情（有實際對話內容代表順利完成）
	if current_dialogue_lines.size() > 0:
		if agent1 and agent1.has_method("on_conversation_result"):
			agent1.on_conversation_result(8.0)
		if agent2 and agent2.has_method("on_conversation_result"):
			agent2.on_conversation_result(8.0)

	# 恢復排程
	if agent1:
		agent1.paused_for_conversation = false
	if agent2:
		agent2.paused_for_conversation = false

	# 儲存記憶（fire-and-forget，不等回應）
	_save_conversation_memory()

	# 記錄本對冷卻
	if agent1 and agent2:
		var key = _get_pair_key(agent1, agent2)
		pair_cooldowns[key] = Time.get_ticks_msec() / 1000.0 + PAIR_COOLDOWN_SEC

	# 通知社交引擎對話結束（在 clear 前讀取結果）
	var _conv_success = current_dialogue_lines.size() > 0
	if agent1:
		var na = current_speaker_names[0]
		var http = HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(func(_r,_c,_h,_b): http.queue_free())
		http.request(SOCIAL_API + "/complete", ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify({"agent_id": na, "success": _conv_success}))

	is_conversation_active = false
	is_displaying_line = false
	current_dialogue_lines.clear()
	current_line_index = 0

	conversation_ended.emit()

func _save_conversation_memory() -> void:
	"""對話結束時，將對話行傳給 Python 記憶系統儲存（fire-and-forget）"""
	if not agent1 or not agent2 or current_dialogue_lines.is_empty():
		return
	var name1 = current_speaker_names[0]
	var name2 = current_speaker_names[1]
	# 取得遊戲時間字串
	var world = get_parent()
	var sim_min = world.sim_clock_minutes if world and "sim_clock_minutes" in world else 0
	var game_time = "%02d:%02d" % [sim_min / 60, sim_min % 60]
	# 組成對話行陣列
	var lines_arr = []
	for line in current_dialogue_lines:
		lines_arr.append({"speaker": line["speaker"], "content": line["content"]})
	var body = JSON.stringify({
		"agent1":         name1,
		"agent2":         name2,
		"game_time":      game_time,
		"dialogue_lines": lines_arr
	})
	_mem_http.request(
		MEMORY_API + "/save",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body
	)
	print("💾 [記憶] 儲存對話摘要：%s ↔ %s @ %s" % [name1, name2, game_time])

func _add_to_history(speaker: String, content: String) -> void:
	"""添加到歷史記錄"""
	var time_dict = Time.get_time_dict_from_system()
	var timestamp = "%02d:%02d" % [time_dict.hour, time_dict.minute]
	
	conversation_history.append({
		"time": timestamp,
		"speaker": speaker,
		"content": content
	})
	
	if history_content:
		var entry = Label.new()
		entry.text = "[%s] %s: %s" % [timestamp, speaker, content]
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_theme_font_size_override("font_size", 10)
		
		# 根據 Agent 設置顏色
		entry.add_theme_color_override("font_color", AGENT_COLORS.get(speaker, Color(0.8, 0.8, 0.8)))
		
		history_content.add_child(entry)
		
		# 自動滾動到底部
		await get_tree().process_frame
		history_scroll.scroll_vertical = history_scroll.get_v_scroll_bar().max_value

# ===== 外部調用 =====

func force_trigger_conversation() -> void:
	"""強制觸發對話（忽略冷卻）"""
	_start_conversation()

func test_llm_connection() -> void:
	if llm_api_manager and llm_api_manager.has_method("test_connection"):
		llm_api_manager.test_connection()

func toggle_history() -> void:
	"""切換歷史記錄顯示"""
	history_visible = not history_visible
	if history_ui:
		history_ui.visible = history_visible

func print_debug_info() -> void:
	print("\n=== 💬 對話系統狀態 ===")
	print("對話中: %s" % is_conversation_active)
	print("對話行數: %d" % current_dialogue_lines.size())
	print("當前行: %d" % current_line_index)
	print("=========================\n")

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F6:
			toggle_history()
	elif event is InputEventMouseButton and history_visible and history_scroll:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			history_scroll.scroll_vertical -= 30
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			history_scroll.scroll_vertical += 30
