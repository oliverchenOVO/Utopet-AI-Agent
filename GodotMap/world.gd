extends Node2D

# ===== Agent 節點 =====
@onready var jack: CharacterBody2D  = $Jack
@onready var mike: CharacterBody2D  = $Mike
@onready var fin:  CharacterBody2D  = $Fin
@onready var buba: CharacterBody2D  = $Buba
@onready var ip_node: Node2D        = $"Interactive points"
@onready var _camera: Camera2D      = $Camera2D

# ===== 相機縮放 =====
const ZOOM_BASE = 0.25   # x1.0：預設全圖視角（84×64 格）
const ZOOM_MIN  = 0.25   # 最遠，不超過預設
const ZOOM_MAX  = 2.0    # 最近：約 10×8 格，可完整看到一間房子
const ZOOM_STEP = 1.15   # 每格滾輪放大 15%

# 地圖邊界（tile 78-161 × tile 0-63，格子 16px）
const MAP_L = 1248.0   # 78  × 16
const MAP_R = 2592.0   # 162 × 16
const MAP_T =    0.0   #  0  × 16
const MAP_B = 1024.0   #  64 × 16

# ===== 可選子系統 =====
var conversation_manager:    Node = null
var deskpet_manager:         Node = null
var agent_status_panel:      Node = null
var conversation_history_ui: Node = null
var story_generator_ui:      Node = null
var speed_control_ui:        Node = null
var terminal_window:         Node = null

# ===== 時間系統 =====
var sim_clock_minutes: int  = 6 * 60   # 從 06:00 開始
var time_speed: float       = 1.0
var _tick: float            = 0.0
var auto_advance_time: bool = true
var _setup_done: bool       = false    # 互動點設好後才開始 tick 排程

# ===== 速度鎖定（對話/故事生成期間自動降至 x1）=====
var _saved_time_speed: float = 1.0    # 鎖定前的速度，結束後還原
var _speed_lock_count: int   = 0      # 計數器：允許對話與生成同時觸發

# ===== 初始化 =====

func _ready() -> void:
	print("🌍 [World] 初始化...")
	_setup_interaction_points.call_deferred()
	_setup_optional_systems.call_deferred()

func _setup_interaction_points() -> void:
	# --- 全域互動點（所有 agent 共用）---
	var gp: Dictionary = {
		"animals":      ip_node.get_node("Animals").global_position,
		"stalls_1":     ip_node.get_node("Stalls 1").global_position,
		"stalls_2":     ip_node.get_node("Stalls 2").global_position,
		"stalls_3":     ip_node.get_node("Stalls 3").global_position,
		"fishing_spot": ip_node.get_node("Fishing spot").global_position,
		"tree_1":       ip_node.get_node("Tree 1").global_position,
		"tree_2":       ip_node.get_node("Tree 2").global_position,
		"tree_3":       ip_node.get_node("Tree 3").global_position,
	}
	for i in range(1, 9):
		gp["crops_%d" % i] = ip_node.get_node("Crops %d" % i).global_position

	for agent in [jack, mike, fin, buba]:
		for key in gp:
			agent.update_interaction_point(key, gp[key])

	# --- Jack 私人標記（在 Jack 移動前讀取 global_position → 世界固定座標）---
	jack.update_interaction_point("jack_home",  $Jack/"Jack home".global_position)
	jack.update_interaction_point("jack_chair", $Jack/"Jack chair".global_position)
	jack.update_interaction_point("jack_bed",   $Jack/"Jack bed".global_position)

	# --- Mike 私人標記 ---
	mike.update_interaction_point("mike_home",  $Mike/"Mike home".global_position)
	mike.update_interaction_point("mike_chair", $Mike/"Mike chair".global_position)
	mike.update_interaction_point("mike_bed",   $Mike/"Mike bed".global_position)

	# --- Fin 私人標記 ---
	fin.update_interaction_point("fin_home",    $Fin/"Fin home".global_position)
	fin.update_interaction_point("fin_chair",   $Fin/"Fin chair".global_position)
	fin.update_interaction_point("fin_bed",     $Fin/"Fin bed".global_position)

	# --- Buba 私人標記 ---
	buba.update_interaction_point("buba_home",  $Buba/"Buba home".global_position)
	buba.update_interaction_point("buba_chair", $Buba/"Buba chair".global_position)
	buba.update_interaction_point("buba_bed",   $Buba/"Buba bed".global_position)

	_setup_done = true
	print("✅ [World] 所有互動點設置完成")
	_print_schedule_preview()

func _setup_optional_systems() -> void:
	var term_script = load("res://terminal_window.gd")
	if term_script:
		terminal_window = term_script.new()
		terminal_window.name = "TerminalWindow"
		add_child(terminal_window)
		terminal_window.log_info("🌍 [World] 系統啟動")
		print("🖥️  [World] 終端視窗已加載")
	else:
		print("⚠️  [World] terminal_window.gd 未找到，跳過")

	var conv_script = load("res://agent_conversation_manager.gd")
	if conv_script:
		conversation_manager = conv_script.new()
		conversation_manager.name = "ConversationManager"
		add_child(conversation_manager)
		# 對話開始 → 速度鎖定 x1；對話結束 → 恢復原速
		conversation_manager.conversation_started.connect(func(_a, _b): _slow_event_start())
		conversation_manager.conversation_ended.connect(_slow_event_end)
		print("💬 [World] 對話管理器已加載")
	else:
		print("⚠️  [World] agent_conversation_manager.gd 未找到，跳過")

	var desk_script = load("res://deskpet_manager.gd")
	if desk_script:
		deskpet_manager = desk_script.new()
		deskpet_manager.name = "DeskPetManager"
		add_child(deskpet_manager)
		print("🐾 [World] 桌寵管理器已加載")
	else:
		print("⚠️  [World] deskpet_manager.gd 未找到，跳過")

	var panel_script = load("res://agent_status_panel.gd")
	if panel_script:
		agent_status_panel = panel_script.new()
		agent_status_panel.name = "AgentStatusPanel"
		add_child(agent_status_panel)
		# 等互動點設好（_setup_done = true）後 agent 節點已就緒，可直接傳入
		agent_status_panel.setup([jack, mike, fin, buba])
		print("📊 [World] Agent 狀態面板已加載")

	var hist_script = load("res://conversation_history_ui.gd")
	if hist_script:
		conversation_history_ui = hist_script.new()
		conversation_history_ui.name = "ConversationHistoryUI"
		add_child(conversation_history_ui)
		if conversation_manager:
			conversation_history_ui.setup(conversation_manager)
		print("📜 [World] 對話歷史 UI 已加載")
	else:
		print("⚠️  [World] conversation_history_ui.gd 未找到，跳過")

	var story_script = load("res://story_generator_ui.gd")
	if story_script:
		story_generator_ui = story_script.new()
		story_generator_ui.name = "StoryGeneratorUI"
		add_child(story_generator_ui)
		story_generator_ui.setup([jack, mike, fin, buba], conversation_manager)
		# 故事生成開始 → 速度鎖定 x1；全部完成 → 恢復原速
		story_generator_ui.generation_started.connect(_slow_event_start)
		story_generator_ui.generation_finished.connect(_slow_event_end)
		print("📚 [World] 故事生成 UI 已加載")

	var speed_script = load("res://speed_control_ui.gd")
	if speed_script:
		speed_control_ui = speed_script.new()
		speed_control_ui.name = "SpeedControlUI"
		add_child(speed_control_ui)
		speed_control_ui.setup(self)
		print("⚙️ [World] 速度控制 UI 已加載")
	else:
		print("⚠️  [World] speed_control_ui.gd 未找到，跳過")

# ===== 主迴圈 =====

func _process(delta: float) -> void:
	if not auto_advance_time:
		return

	_tick += delta * time_speed
	if _tick >= 1.0:
		_tick -= 1.0
		sim_clock_minutes += 1
		if sim_clock_minutes >= 24 * 60:
			sim_clock_minutes = 0
			_on_new_day()
		_update_title()

	if _setup_done:
		jack.tick_schedule(sim_clock_minutes)
		mike.tick_schedule(sim_clock_minutes)
		fin.tick_schedule(sim_clock_minutes)
		buba.tick_schedule(sim_clock_minutes)
		jack.tick_stats(sim_clock_minutes)
		mike.tick_stats(sim_clock_minutes)
		fin.tick_stats(sim_clock_minutes)
		buba.tick_stats(sim_clock_minutes)

func _on_new_day() -> void:
	print("🌅 [World] 新的一天開始")
	for agent in [jack, mike, fin, buba]:
		agent.reset_schedule()

func _update_title() -> void:
	var hh = sim_clock_minutes / 60
	var mm = sim_clock_minutes % 60
	get_tree().root.title = "Utopian Town — %02d:%02d  (x%.0f)" % [hh, mm, time_speed]

# ===== 工具 =====

func _format_time(minutes: int) -> String:
	return "%02d:%02d" % [minutes / 60, minutes % 60]

func _print_schedule_preview() -> void:
	print("\n=== 📅 今日行程預覽 ===")
	for agent in [jack, mike, fin, buba]:
		print("  [%s]" % agent.agent_name)
		for task in agent.schedule:
			print("    %s  %s → %s" % [_format_time(task.time), task.description, task.target])
	print("=====================\n")

# ===== 鍵盤控制 =====

func _input(event: InputEvent) -> void:
	# ── 滾輪縮放（朝光標方向）──
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at_cursor(ZOOM_STEP, event.position)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at_cursor(1.0 / ZOOM_STEP, event.position)
			return

	# ── 鍵盤控制 ──
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_T:
			_toggle_speed()
		KEY_P:
			auto_advance_time = not auto_advance_time
			print("⏸️  時間%s" % ("恢復" if auto_advance_time else "暫停"))
		KEY_R:
			_reset_world()
		KEY_I:
			_print_status()
		KEY_H:
			_print_schedule_preview()
		KEY_M:
			_toggle_mouse_move()
		KEY_S:
			for a in [jack, mike, fin, buba]:
				a.stop_movement()
			print("🛑 所有 Agent 停止")
		KEY_F1:
			jack.force_next_schedule()
		KEY_F2:
			mike.force_next_schedule()
		KEY_F3:
			fin.force_next_schedule()
		KEY_F4:
			buba.force_next_schedule()

func _zoom_at_cursor(factor: float, _unused: Vector2) -> void:
	var old_z: float = _camera.zoom.x
	var new_z: float = clamp(old_z * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_z, old_z):
		return
	# 使用 get_mouse_position() 取得正確的 viewport 座標（336×256 空間）
	# event.position 是視窗像素座標，在 integer-scale 模式下會放大 4 倍，不能直接用
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var mouse:   Vector2 = get_viewport().get_mouse_position()
	var offset:  Vector2 = mouse - vp_size * 0.5
	# 保持光標下的世界座標不動：camera 往相反方向補偏移
	_camera.position += offset / old_z - offset / new_z
	_camera.zoom      = Vector2(new_z, new_z)
	_clamp_camera()

func _clamp_camera() -> void:
	# 根據當前 zoom 計算相機中心的合法範圍，防止露出地圖外的灰邊
	var vp:    Vector2 = get_viewport().get_visible_rect().size
	var z:     float   = _camera.zoom.x
	var half_w: float  = vp.x * 0.5 / z
	var half_h: float  = vp.y * 0.5 / z
	# 若視野比地圖還寬/高（縮得太遠），就直接置中
	var cx: float = _camera.position.x
	var cy: float = _camera.position.y
	if half_w * 2.0 >= MAP_R - MAP_L:
		cx = (MAP_L + MAP_R) * 0.5
	else:
		cx = clamp(cx, MAP_L + half_w, MAP_R - half_w)
	if half_h * 2.0 >= MAP_B - MAP_T:
		cy = (MAP_T + MAP_B) * 0.5
	else:
		cy = clamp(cy, MAP_T + half_h, MAP_B - half_h)
	_camera.position = Vector2(cx, cy)

func _toggle_mouse_move() -> void:
	var enabled = not jack.mouse_move_enabled
	for a in [jack, mike, fin, buba]:
		a.mouse_move_enabled = enabled
	print("🖱️  滑鼠點擊移動: %s" % ("開啟" if enabled else "關閉"))

func _toggle_speed() -> void:
	var speeds: Array = [1.0, 2.0, 5.0, 10.0, 30.0]
	var idx = speeds.find(time_speed)
	if idx == -1:
		idx = 0
	time_speed = speeds[(idx + 1) % speeds.size()]
	print("⏩ 時間速度: x%.0f" % time_speed)

func _reset_world() -> void:
	sim_clock_minutes = 6 * 60
	_tick = 0.0
	for agent in [jack, mike, fin, buba]:
		agent.reset_schedule()
	print("🔄 重置到 06:00")

# ===== 速度鎖定（對話 / 故事生成期間自動 x1）=====

func _slow_event_start() -> void:
	_speed_lock_count += 1
	if _speed_lock_count == 1:
		# 第一個事件開始時才存速度、降速
		_saved_time_speed = time_speed
		time_speed = 1.0
		auto_advance_time = true   # 確保時間在運行（不影響暫停鍵）
		print("⏬ [World] 速度鎖定 x1（對話/生成中，原速 x%.0f）" % _saved_time_speed)

func _slow_event_end() -> void:
	_speed_lock_count = max(0, _speed_lock_count - 1)
	if _speed_lock_count == 0:
		# 所有事件都結束後才恢復
		if _saved_time_speed != 1.0:
			time_speed = _saved_time_speed
			print("⏫ [World] 速度恢復 x%.0f" % time_speed)
		else:
			print("✅ [World] 對話/生成結束（速度維持 x1）")

func _print_status() -> void:
	print("\n=== 🌍 世界狀態 %s ===" % _format_time(sim_clock_minutes))
	print("  時間速度: x%.0f  自動推進: %s" % [time_speed, auto_advance_time])
	for a in [jack, mike, fin, buba]:
		var s = a.get_status()
		print("  [%s] 飢餓:%.0f  疲憊:%.0f  心情:%.0f  moving:%s  排程:%d/%d" % [
			s.name, s.hunger, s.fatigue, s.mood_value, s.is_moving,
			a.schedule_index, a.schedule.size()])
	print("====================\n")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
