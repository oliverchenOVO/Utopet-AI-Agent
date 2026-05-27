extends CharacterBody2D

# ===== 角色身份 =====
# 名稱：Mike　職業：礦工（目前休假，心情愉快，在小鎮四處遊走）
# 綁定節點：Mike（CharacterBody2D）
# 每天從三種日程表隨機挑一種，確保三餐和睡眠固定，白天路線各異

const SPEED: float = 150.0
const SOCIAL_API   = "http://127.0.0.1:8000"

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var _check_area: Area2D = $Area2D

var _is_ready: bool = false
var _building_overlap_count: int = 0

var agent_name: String = "Mike"
var agent_id: int      = 1
var mood: String       = "愉快"
var interaction_points: Dictionary = {}
var paused_for_conversation: bool = false

# ===== 生理數值 =====
const HUNGER_RATE   = 0.20   # 原 0.35
const FATIGUE_MOVE  = 0.10   # 原 0.25
const FATIGUE_WORK  = 0.04   # 原 0.08
const FATIGUE_SLEEP = -3.0
const MOOD_DECAY    = 0.03   # 原 0.04
const MOOD_RECOVERY = 0.15   # 原 0.12

var hunger: float     = 10.0
var fatigue: float    = 0.0
var mood_value: float = 75.0
var _last_stat_min: int = 6 * 60

# ===== 三種日程表（每天隨機挑一種）=====
const SCHEDULE_VARIANTS: Array = [
	# A：市集巡禮 — 沿著攤位一路閒逛
	[
		{"time": 6*60+30, "target": "mike_bed",    "arrive_anim": "Bed",        "description": "起床"},
		{"time": 7*60,    "target": "mike_chair",  "arrive_anim": "Idle Front", "description": "吃早餐",  "is_meal": true},
		{"time": 8*60,    "target": "stalls_1",    "arrive_anim": "Idle Front", "description": "逛市集 1"},
		{"time": 9*60+30, "target": "stalls_2",    "arrive_anim": "Idle Front", "description": "逛市集 2"},
		{"time": 11*60,   "target": "fishing_spot","arrive_anim": "Idle Right", "description": "看人釣魚"},
		{"time": 12*60+30,"target": "stalls_3",    "arrive_anim": "Idle Front", "description": "午餐",    "is_meal": true},
		{"time": 14*60,   "target": "stalls_1",    "arrive_anim": "Idle Front", "description": "下午閒逛"},
		{"time": 15*60+30,"target": "animals",     "arrive_anim": "Idle Front", "description": "看看動物"},
		{"time": 17*60,   "target": "mike_home",   "arrive_anim": "Idle Front", "description": "回家"},
		{"time": 18*60,   "target": "mike_chair",  "arrive_anim": "Idle Front", "description": "吃晚餐",  "is_meal": true},
		{"time": 20*60,   "target": "mike_bed",    "arrive_anim": "Bed",        "description": "就寢"},
	],
	# B：自然漫步 — 樹林、溪邊、農田繞一圈
	[
		{"time": 6*60+30, "target": "mike_bed",    "arrive_anim": "Bed",        "description": "起床"},
		{"time": 7*60,    "target": "mike_chair",  "arrive_anim": "Idle Front", "description": "吃早餐",  "is_meal": true},
		{"time": 8*60,    "target": "tree_1",      "arrive_anim": "Idle Right", "description": "散步到樹林"},
		{"time": 9*60+30, "target": "fishing_spot","arrive_anim": "Idle Right", "description": "到溪邊走走"},
		{"time": 11*60,   "target": "crops_1",     "arrive_anim": "Idle Front", "description": "看看農田"},
		{"time": 12*60+30,"target": "stalls_2",    "arrive_anim": "Idle Front", "description": "午餐",    "is_meal": true},
		{"time": 14*60,   "target": "tree_2",      "arrive_anim": "Idle Right", "description": "下午散步"},
		{"time": 15*60+30,"target": "animals",     "arrive_anim": "Idle Front", "description": "看動物"},
		{"time": 17*60,   "target": "mike_home",   "arrive_anim": "Idle Front", "description": "回家"},
		{"time": 18*60,   "target": "mike_chair",  "arrive_anim": "Idle Front", "description": "吃晚餐",  "is_meal": true},
		{"time": 20*60,   "target": "mike_bed",    "arrive_anim": "Bed",        "description": "就寢"},
	],
	# C：鄰里閒晃 — 在家附近和集市間慢慢打發時間
	[
		{"time": 6*60+30, "target": "mike_bed",    "arrive_anim": "Bed",        "description": "起床"},
		{"time": 7*60,    "target": "mike_chair",  "arrive_anim": "Idle Front", "description": "吃早餐",  "is_meal": true},
		{"time": 8*60,    "target": "stalls_2",    "arrive_anim": "Idle Front", "description": "早上閒逛"},
		{"time": 10*60,   "target": "animals",     "arrive_anim": "Idle Front", "description": "探望動物"},
		{"time": 12*60,   "target": "stalls_1",    "arrive_anim": "Idle Front", "description": "午餐",    "is_meal": true},
		{"time": 13*60+30,"target": "fishing_spot","arrive_anim": "Idle Right", "description": "到溪邊散步"},
		{"time": 15*60,   "target": "stalls_3",    "arrive_anim": "Idle Front", "description": "下午閒逛"},
		{"time": 17*60,   "target": "mike_home",   "arrive_anim": "Idle Front", "description": "回家休息"},
		{"time": 18*60,   "target": "mike_chair",  "arrive_anim": "Idle Front", "description": "吃晚餐",  "is_meal": true},
		{"time": 20*60,   "target": "mike_bed",    "arrive_anim": "Bed",        "description": "就寢"},
	],
]

const SCHEDULE_NAMES: Array = ["市集巡禮", "自然漫步", "鄰里閒晃"]

var schedule: Array        = []
var _day_number: int       = 1   # Day 1 固定市集巡禮；Day 2 起 LLM / 數值選擇
var _http_schedule: HTTPRequest = null

var mouse_move_enabled: bool  = false
var schedule_index: int       = 0
var _arrive_anim: String      = ""
var _arrive_anim_played: bool = false

# ===== 初始化 =====

func _ready() -> void:
	_check_area.area_entered.connect(_on_building_entered)
	_check_area.area_exited.connect(_on_building_exited)
	_http_schedule = HTTPRequest.new()
	_http_schedule.timeout = 25.0
	add_child(_http_schedule)
	_http_schedule.request_completed.connect(_on_schedule_response)
	actor_setup.call_deferred()

func _on_building_entered(area: Area2D) -> void:
	if area.name == "Buildings":
		_building_overlap_count += 1
		var tw = create_tween()
		tw.tween_property(self, "modulate:a", 0.5, 0.15)

func _on_building_exited(area: Area2D) -> void:
	if area.name == "Buildings":
		_building_overlap_count = max(0, _building_overlap_count - 1)
		if _building_overlap_count == 0:
			var tw = create_tween()
			tw.tween_property(self, "modulate:a", 1.0, 0.15)

func actor_setup() -> void:
	await NavigationServer2D.map_changed
	_is_ready = true
	schedule = SCHEDULE_VARIANTS[0].duplicate(true)
	_play_animation("Idle", "Front")
	print("⛏️  [Mike] 導航就緒 — Day 1 固定日程：【%s】" % SCHEDULE_NAMES[0])

# ===== 排程接口 =====

func tick_schedule(sim_minutes: int) -> void:
	if paused_for_conversation:
		return
	if schedule_index >= schedule.size():
		return
	if sim_minutes >= schedule[schedule_index].time:
		_execute_task(schedule[schedule_index])
		schedule_index += 1

func _execute_task(task: Dictionary) -> void:
	print("⛏️  [Mike] %s → %s" % [task.description, task.target])
	_arrive_anim = task.get("arrive_anim", "")
	_arrive_anim_played = false
	if task.get("is_meal", false):
		on_meal()
	move_to_interaction_point_with_type(task.target, "", "")

func reset_schedule() -> void:
	schedule_index = 0
	_last_stat_min = 0
	_day_number   += 1
	if _day_number == 1:
		schedule = SCHEDULE_VARIANTS[0].duplicate(true)
		print("⛏️  [Mike] Day 1 固定日程：【%s】" % SCHEDULE_NAMES[0])
	else:
		_apply_stats_schedule()
		_request_llm_schedule()

func _apply_stats_schedule() -> void:
	var idx: int
	if fatigue > 60.0:
		idx = 2   # 鄰里閒晃（不走遠）
	elif mood_value > 75.0:
		idx = 1   # 自然漫步
	else:
		idx = 0   # 市集巡禮
	schedule = SCHEDULE_VARIANTS[idx].duplicate(true)
	print("⛏️  [Mike] Day%d 數值fallback → 【%s】（疲:%0.f 情:%0.f）" % [_day_number, SCHEDULE_NAMES[idx], fatigue, mood_value])

func _request_llm_schedule() -> void:
	var body = JSON.stringify({
		"agent":      agent_name,
		"hunger":     hunger,
		"fatigue":    fatigue,
		"mood_value": mood_value,
	})
	var err = _http_schedule.request(
		SOCIAL_API + "/schedule/suggest_variant",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST, body
	)
	if err != OK:
		print("⛏️  [Mike] 日程 API 請求失敗，保留數值 fallback")

func _on_schedule_response(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("⛏️  [Mike] 日程 API 失敗（result=%d code=%d），保留 fallback" % [result, code])
		return
	if schedule_index > 0:
		print("⛏️  [Mike] LLM 回應已來不及（任務已開始），保留當前日程")
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var data = json.data
	var idx: int = int(data.get("variant_index", -1))
	if idx < 0 or idx >= SCHEDULE_VARIANTS.size():
		return
	schedule = SCHEDULE_VARIANTS[idx].duplicate(true)
	print("⛏️  [Mike] LLM 建議日程：【%s】（%s）" % [SCHEDULE_NAMES[idx], data.get("reason", "")])

func force_next_schedule() -> void:
	if schedule_index < schedule.size():
		_execute_task(schedule[schedule_index])
		schedule_index += 1
		print("🔧 [Mike] 強制下一個排程")

# ===== 輸入 =====

func _unhandled_input(event: InputEvent) -> void:
	if not _is_ready or not mouse_move_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		navigation_agent.target_position = get_global_mouse_position()
		_arrive_anim = ""
		_arrive_anim_played = false

# ===== 物理更新 =====

func _physics_process(_delta: float) -> void:
	if not _is_ready:
		return

	if navigation_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		move_and_slide()
		if not _arrive_anim_played and _arrive_anim != "":
			_play_arrive_animation(_arrive_anim)
			_arrive_anim_played = true
		elif _arrive_anim == "":
			_update_animation(Vector2.ZERO)
		return

	_arrive_anim_played = false
	var next_pos: Vector2  = navigation_agent.get_next_path_position()
	var direction: Vector2 = global_position.direction_to(next_pos)
	velocity = direction * SPEED
	_update_animation(velocity)
	move_and_slide()

# ===== 動畫 =====

var _last_direction: String = "Front"

func _update_animation(vel: Vector2) -> void:
	var is_moving: bool = vel.length() > 0.1
	if is_moving:
		if abs(vel.y) >= abs(vel.x):
			_last_direction = "Back" if vel.y < 0 else "Front"
			_play_animation("Walk", _last_direction)
		else:
			_last_direction = "Right"
			_play_animation("Walk", "Right")
			animated_sprite.flip_h = vel.x < 0
	else:
		_play_animation("Idle", _last_direction)

func _play_animation(state: String, direction: String) -> void:
	var anim_name: String = state + " " + direction
	if animated_sprite.animation == anim_name and animated_sprite.is_playing():
		return
	if direction != "Right":
		animated_sprite.flip_h = false
	animated_sprite.play(anim_name)

func _play_arrive_animation(anim: String) -> void:
	if anim.is_empty():
		return
	if anim == "Bed":
		animated_sprite.flip_h = false
		animated_sprite.rotation_degrees = 0.0
		animated_sprite.play("Idle Front")
	elif anim.ends_with(" Left"):
		animated_sprite.flip_h = true
		animated_sprite.play(anim.replace(" Left", " Right"))
	else:
		animated_sprite.flip_h = false
		animated_sprite.play(anim)

# ===== 生理數值接口 =====

func tick_stats(sim_minutes: int) -> void:
	var elapsed = sim_minutes - _last_stat_min
	if elapsed <= 0:
		return
	_last_stat_min = sim_minutes

	hunger = clamp(hunger + HUNGER_RATE * elapsed, 0.0, 100.0)

	var is_sleeping = (_arrive_anim == "Bed")
	var is_moving   = not navigation_agent.is_navigation_finished()
	if is_sleeping:
		fatigue = clamp(fatigue + FATIGUE_SLEEP * elapsed, 0.0, 100.0)
	elif is_moving:
		fatigue = clamp(fatigue + FATIGUE_MOVE * elapsed, 0.0, 100.0)
	else:
		fatigue = clamp(fatigue + FATIGUE_WORK * elapsed, 0.0, 100.0)

	if mood_value > 50.0:
		mood_value = clamp(mood_value - MOOD_DECAY * elapsed, 50.0, 100.0)
	else:
		mood_value = clamp(mood_value + MOOD_RECOVERY * elapsed, 0.0, 50.0)

func on_meal() -> void:
	hunger     = clamp(hunger - 75.0, 0.0, 100.0)
	mood_value = clamp(mood_value + 5.0, 0.0, 100.0)
	print("🍽️  [Mike] 用餐 → 飢餓:%.0f  心情:%.0f" % [hunger, mood_value])

func on_conversation_result(delta: float) -> void:
	mood_value = clamp(mood_value + delta, 0.0, 100.0)

# ===== 模擬系統接口 =====

func update_interaction_point(p_name: String, p_pos: Vector2) -> void:
	interaction_points[p_name] = p_pos

func get_available_interaction_points() -> Array:
	return interaction_points.keys()

func move_to_interaction_point_with_type(target_name: String, _type: String, _emoji: String) -> void:
	if not interaction_points.has(target_name):
		push_warning("⛏️  [Mike] 找不到交互點: %s" % target_name)
		return
	if not _is_ready:
		push_warning("⛏️  [Mike] 導航尚未就緒")
		return
	animated_sprite.rotation_degrees = 0.0
	_arrive_anim_played = false
	navigation_agent.target_position = interaction_points[target_name]

func stop_movement() -> void:
	navigation_agent.target_position = global_position
	velocity = Vector2.ZERO
	move_and_slide()
	_arrive_anim = ""
	_update_animation(Vector2.ZERO)

func get_status() -> Dictionary:
	return {
		"name":       agent_name,
		"id":         agent_id,
		"mood":       mood,
		"hunger":     hunger,
		"fatigue":    fatigue,
		"mood_value": mood_value,
		"position":   global_position,
		"is_moving":  not navigation_agent.is_navigation_finished(),
	}
