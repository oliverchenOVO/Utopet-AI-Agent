# story_generator_ui.gd
# 📚 故事生成 UI：按鈕 → 橢圓 Agent 選擇器 → 故事列表 → 故事閱覽
# 20:00 自動觸發；手動點擊亦可；四篇故事平行請求，全部完成後存檔
# 啟動時自動載入歷史故事（user://stories/<AgentName>/story_*.txt）
extends CanvasLayer

# ===== 信號（供 world.gd 監聽以鎖定速度）=====
signal generation_started()
signal generation_finished()

# ===== 佈局常數（與其他兩個面板風格一致）=====
const BTN_SZ      = 20
const BTN_MARGIN  = 5
const BTN_GAP     = 4
const SHIFT_LEFT  = 30

const CIRCLE_SZ   = 30
const POPUP_GAP   = 4
const POPUP_H     = 46
const POPUP_W     = 154

const PANEL_W     = 210
const PANEL_H     = 155

# ===== Ollama =====
const OLLAMA_URL   = "http://127.0.0.1:11434/api/generate"
const OLLAMA_MODEL = "qwen2.5:1.5b"   # 故事專用小模型，速度快 10-20 倍

# ===== 存檔 =====
# 存到專案目錄下的 stories/ 資料夾（res:// 在編輯器下 = 專案根目錄）
var _stories_dir: String = ""

# ===== Agent 設定 =====
const AGENT_NAMES  = ["Jack", "Mike", "Fin", "Buba"]
const AGENT_EMOJIS = ["🪓",   "⛏️",  "🎣",  "🌾"]
const AGENT_COLORS = {
	"Jack": Color(0.9,  0.5,  0.1,  1.0),
	"Mike": Color(0.6,  0.6,  0.7,  1.0),
	"Fin":  Color(0.2,  0.6,  0.9,  1.0),
	"Buba": Color(0.2,  0.7,  0.3,  1.0),
}
const AGENT_ROLES = {
	"Jack": "伐木工，個性勤奮踏實，喜歡在森林裡工作",
	"Mike": "礦工，沉默寡言，對採礦工作充滿熱情",
	"Fin":  "釣魚人，悠閒自在，享受湖邊寧靜的時光",
	"Buba": "農夫，熱心助人，對農田與動物充滿愛",
}

const PANEL_BG    = Color(0.07, 0.07, 0.12, 0.94)
const CELL_BG     = Color(0.10, 0.10, 0.16, 0.95)
const DEFAULT_CLR = Color(0.6, 0.6, 0.6)

# ===== 狀態 =====
var _agents:                Array      = []
var _conv_manager:          Node       = null
var _stories:               Dictionary = {}   # {agent_name: story_text}（當前生成批次暫存）
var _story_list:            Dictionary = {}   # {agent_name: [{stamp, text}]}（永久列表）
var _generating:            bool       = false
var _gen_stamp:             String     = ""   # 本次生成批次的時間戳
var _story_generated_today: bool       = false
var _prev_minute:           int        = -1

var _selected_agent: String = ""   # 當前列表顯示的 agent

# ===== UI 節點 =====
var _root_ctrl: Control
var _story_btn: Button

var _popup:      PanelContainer
var _popup_open: bool = false

var _panel:      PanelContainer
var _panel_open: bool = false

# 列表視圖
var _list_view:      VBoxContainer
var _list_scroll:    ScrollContainer
var _list_content:   VBoxContainer
var _list_title_lbl: Label

# 詳細視圖
var _detail_view:      VBoxContainer
var _detail_title_lbl: Label
var _detail_body_lbl:  Label
var _detail_scroll:    ScrollContainer

# HTTP（平行生成，每個 Agent 各一個節點）
var _http_pool: Array = []   # 4 個 HTTPRequest，index 對應 AGENT_NAMES
var _done_count: int  = 0    # 收到幾篇完成回應

# ===== 初始化 =====

func _ready() -> void:
	layer = 22
	_stories_dir = ProjectSettings.globalize_path("res://stories")
	_build_ui()
	_setup_http()
	_init_story_list()
	_load_existing_stories()
	print("📚 [StoryGen] 故事將存至：", _stories_dir)

func _init_story_list() -> void:
	for aname in AGENT_NAMES:
		_story_list[aname] = []

func _load_existing_stories() -> void:
	var total = 0
	for aname in AGENT_NAMES:
		var agent_dir = _stories_dir + "/" + aname
		var dir = DirAccess.open(agent_dir)
		if not dir:
			continue
		var files: Array = []
		dir.list_dir_begin()
		var fname = dir.get_next()
		while fname != "":
			if fname.ends_with(".json") and fname.begins_with("story_"):
				files.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()

		files.sort()
		files.reverse()   # 最新在前

		for fname2 in files:
			var fpath = agent_dir + "/" + fname2
			var file = FileAccess.open(fpath, FileAccess.READ)
			if not file:
				continue
			var raw = file.get_as_text()
			file.close()

			var json = JSON.new()
			if json.parse(raw) != OK:
				continue
			var data = json.data
			var entries: Array = data.get("entries", [])
			var body = "\n".join(entries)
			var stamp = data.get("stamp", fname2.trim_prefix("story_").trim_suffix(".json"))
			_story_list[aname].append({"stamp": stamp, "text": body})
			total += 1

	print("📚 [StoryGen] 已載入 %d 篇歷史日誌" % total)

func setup(agent_list: Array, conv_manager: Node = null) -> void:
	"""由 world.gd 呼叫"""
	_agents       = agent_list
	_conv_manager = conv_manager

func _setup_http() -> void:
	for i in range(4):
		var http = HTTPRequest.new()
		http.timeout = 45.0   # 1.5b 模型 45 秒內肯定能完成
		add_child(http)
		# 用 lambda 把 agent index 綁進 callback
		http.request_completed.connect(
			func(result, code, _h, body): _on_story_received(i, result, code, body)
		)
		_http_pool.append(http)

# ===== 20:00 自動觸發 =====

func _process(_delta: float) -> void:
	var p = get_parent()
	if not p or not "sim_clock_minutes" in p:
		return
	var cur: int = p.sim_clock_minutes
	if cur == _prev_minute:
		return
	_prev_minute = cur

	if cur == 0:
		_story_generated_today = false
	elif cur == 20 * 60 and not _story_generated_today and not _generating:
		_story_generated_today = true
		_generate_all_stories()

# ===== 建構 UI =====

func _build_ui() -> void:
	_root_ctrl = Control.new()
	_root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_ctrl)
	_build_story_button()
	_build_popup()
	_build_panel()

func _build_story_button() -> void:
	_story_btn = Button.new()
	_story_btn.text = "📚"
	_story_btn.custom_minimum_size = Vector2(BTN_SZ, BTN_SZ)
	_story_btn.focus_mode = Control.FOCUS_NONE
	_story_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

	# 第三個按鈕，位於 💬 上方
	_story_btn.anchor_left   = 1.0
	_story_btn.anchor_right  = 1.0
	_story_btn.anchor_top    = 1.0
	_story_btn.anchor_bottom = 1.0
	_story_btn.offset_left   = -(BTN_SZ + BTN_MARGIN)
	_story_btn.offset_right  = -BTN_MARGIN
	_story_btn.offset_bottom = -(BTN_SZ * 2 + BTN_MARGIN + BTN_GAP * 2)
	_story_btn.offset_top    = -(BTN_SZ * 3 + BTN_MARGIN + BTN_GAP * 2)

	var r = BTN_SZ / 2
	_story_btn.add_theme_stylebox_override("normal",
		_round_style(Color(0.14, 0.14, 0.20, 0.93), Color(0.50, 0.50, 0.75), r))
	_story_btn.add_theme_stylebox_override("hover",
		_round_style(Color(0.20, 0.22, 0.32, 0.97), Color(0.70, 0.72, 0.95), r))
	_story_btn.add_theme_stylebox_override("pressed",
		_round_style(Color(0.10, 0.10, 0.18, 0.97), Color(0.85, 0.85, 1.00), r))
	_story_btn.add_theme_stylebox_override("disabled",
		_round_style(Color(0.10, 0.10, 0.15, 0.55), Color(0.25, 0.25, 0.40), r))
	_story_btn.add_theme_font_size_override("font_size", 9)
	_story_btn.pressed.connect(_on_story_btn_pressed)
	_root_ctrl.add_child(_story_btn)

func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.anchor_left   = 1.0
	_popup.anchor_right  = 1.0
	_popup.anchor_top    = 1.0
	_popup.anchor_bottom = 1.0
	_popup.offset_right  = -(BTN_MARGIN + SHIFT_LEFT)
	_popup.offset_left   = -(POPUP_W + BTN_MARGIN + SHIFT_LEFT)
	_popup.clip_contents = true
	_popup.visible       = false

	var bg = StyleBoxFlat.new()
	bg.bg_color     = PANEL_BG
	bg.border_color = Color(0.40, 0.40, 0.65)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(23)
	bg.content_margin_left   = 8
	bg.content_margin_right  = 8
	bg.content_margin_top    = 5
	bg.content_margin_bottom = 5
	_popup.add_theme_stylebox_override("panel", bg)
	_root_ctrl.add_child(_popup)

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 6)
	_popup.add_child(hbox)

	for i in range(4):
		var aname = AGENT_NAMES[i]
		var btn   = Button.new()
		btn.custom_minimum_size = Vector2(CIRCLE_SZ, CIRCLE_SZ)
		btn.focus_mode  = Control.FOCUS_NONE
		btn.text        = AGENT_EMOJIS[i]
		btn.tooltip_text = aname
		btn.add_theme_font_size_override("font_size", 14)

		var cs = StyleBoxFlat.new()
		cs.bg_color     = AGENT_COLORS.get(aname, DEFAULT_CLR)
		cs.border_color = cs.bg_color.lightened(0.3)
		cs.set_border_width_all(2)
		cs.set_corner_radius_all(CIRCLE_SZ / 2)
		cs.content_margin_left   = 0;  cs.content_margin_right  = 0
		cs.content_margin_top    = 0;  cs.content_margin_bottom = 0
		btn.add_theme_stylebox_override("normal", cs)

		var csh = cs.duplicate()
		csh.bg_color = cs.bg_color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", csh)

		btn.pressed.connect(func(): _open_story_list(aname))
		hbox.add_child(btn)

func _build_panel() -> void:
	var shared_bottom = -(BTN_SZ * 3 + BTN_MARGIN + BTN_GAP * 2 + POPUP_GAP)
	_panel = PanelContainer.new()
	_panel.anchor_left   = 1.0
	_panel.anchor_right  = 1.0
	_panel.anchor_top    = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_right  = -(BTN_MARGIN + SHIFT_LEFT)
	_panel.offset_left   = -(PANEL_W + BTN_MARGIN + SHIFT_LEFT)
	_panel.offset_bottom = shared_bottom
	_panel.offset_top    = shared_bottom - PANEL_H
	_panel.visible       = false
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)

	var bg = StyleBoxFlat.new()
	bg.bg_color     = PANEL_BG
	bg.border_color = Color(0.40, 0.40, 0.65)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	bg.content_margin_left   = 6;  bg.content_margin_right  = 6
	bg.content_margin_top    = 6;  bg.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", bg)
	_root_ctrl.add_child(_panel)

	var wrapper = VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 0)
	_panel.add_child(wrapper)

	_build_list_view(wrapper)
	_build_detail_view(wrapper)

	_list_view.visible   = false
	_detail_view.visible = false

# ===== 列表視圖 =====

func _build_list_view(parent: Control) -> void:
	_list_view = VBoxContainer.new()
	_list_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_view.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_list_view.add_theme_constant_override("separation", 4)
	parent.add_child(_list_view)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	_list_view.add_child(header)

	_list_title_lbl = Label.new()
	_list_title_lbl.text = "📚 故事列表"
	_list_title_lbl.add_theme_font_size_override("font_size", 8)
	_list_title_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_list_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_list_title_lbl)

	header.add_child(_build_close_btn())

	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_list_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_view.add_child(_list_scroll)

	_list_content = VBoxContainer.new()
	_list_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_content.add_theme_constant_override("separation", 3)
	_list_scroll.add_child(_list_content)

# ===== 詳細視圖 =====

func _build_detail_view(parent: Control) -> void:
	_detail_view = VBoxContainer.new()
	_detail_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_view.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_detail_view.add_theme_constant_override("separation", 4)
	parent.add_child(_detail_view)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	_detail_view.add_child(header)

	var back_btn = Button.new()
	back_btn.text = "◀"
	back_btn.custom_minimum_size = Vector2(18, 14)
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_font_size_override("font_size", 7)
	_style_small_btn(back_btn)
	back_btn.pressed.connect(_show_list_view)
	header.add_child(back_btn)

	_detail_title_lbl = Label.new()
	_detail_title_lbl.add_theme_font_size_override("font_size", 8)
	_detail_title_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_detail_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_detail_title_lbl)

	header.add_child(_build_close_btn())

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_view.add_child(_detail_scroll)

	_detail_body_lbl = Label.new()
	_detail_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body_lbl.add_theme_font_size_override("font_size", 7)
	_detail_body_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	_detail_body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.add_child(_detail_body_lbl)

# ===== 互動邏輯 =====

func _on_story_btn_pressed() -> void:
	if _generating:
		return
	if _popup_open:
		_close_popup()
	else:
		_close_panel()
		_open_popup()

func _open_popup() -> void:
	_popup_open = true
	var bottom_y = float(-(BTN_SZ * 3 + BTN_MARGIN + BTN_GAP * 2 + POPUP_GAP))
	_popup.offset_bottom = bottom_y
	_popup.offset_top    = bottom_y
	_popup.visible       = true

	var tween = create_tween()
	tween.tween_property(_popup, "offset_top", bottom_y - POPUP_H, 0.22)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _close_popup() -> void:
	if not _popup_open:
		return
	_popup_open = false
	var tween = create_tween()
	tween.tween_property(_popup, "offset_top", _popup.offset_bottom, 0.18)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	await tween.finished
	_popup.visible = false

func _open_story_list(aname: String) -> void:
	_popup_open     = false
	_popup.visible  = false
	_selected_agent = aname

	var idx = AGENT_NAMES.find(aname)
	var emoji = AGENT_EMOJIS[idx] if idx >= 0 else "📚"
	_list_title_lbl.text = "%s %s 的故事" % [emoji, aname]

	_rebuild_list_content(aname)

	_list_view.visible   = true
	_detail_view.visible = false
	_panel.visible       = true
	_panel_open          = true

func _rebuild_list_content(aname: String) -> void:
	for child in _list_content.get_children():
		child.queue_free()

	var stories = _story_list.get(aname, [])

	# 生成中顯示頂部提示列
	if _generating and _stories.get(aname, "") == "LOADING":
		_append_loading_entry()

	if stories.is_empty() and not (_generating and _stories.get(aname, "") == "LOADING"):
		var empty_lbl = Label.new()
		empty_lbl.text = "（尚無故事。等待 20:00 自動生成，\n或點擊「📚」手動觸發。）"
		empty_lbl.add_theme_font_size_override("font_size", 7)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_content.add_child(empty_lbl)
	else:
		for i in range(stories.size()):
			_append_story_entry(aname, i)

func _append_loading_entry() -> void:
	var entry = PanelContainer.new()
	var es = StyleBoxFlat.new()
	es.bg_color     = Color(0.12, 0.12, 0.20, 0.95)
	es.border_color = Color(0.30, 0.30, 0.55)
	es.set_border_width_all(1)
	es.set_corner_radius_all(4)
	es.content_margin_left = 4;  es.content_margin_right  = 4
	es.content_margin_top  = 3;  es.content_margin_bottom = 3
	entry.add_theme_stylebox_override("panel", es)
	_list_content.add_child(entry)

	var lbl = Label.new()
	lbl.text = "⏳ 生成中，請稍候…"
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	entry.add_child(lbl)

func _append_story_entry(aname: String, idx: int) -> void:
	var stories = _story_list.get(aname, [])
	if idx >= stories.size():
		return
	var story  = stories[idx]
	var stamp: String = story.get("stamp", "")

	var entry = PanelContainer.new()
	var es = StyleBoxFlat.new()
	es.bg_color     = CELL_BG
	es.border_color = Color(0.25, 0.25, 0.45)
	es.set_border_width_all(1)
	es.set_corner_radius_all(4)
	es.content_margin_left = 4;  es.content_margin_right  = 4
	es.content_margin_top  = 3;  es.content_margin_bottom = 3
	entry.add_theme_stylebox_override("panel", es)
	_list_content.add_child(entry)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	entry.add_child(row)

	var read_btn = Button.new()
	read_btn.text = "閱讀"
	read_btn.custom_minimum_size = Vector2(28, 14)
	read_btn.focus_mode = Control.FOCUS_NONE
	read_btn.add_theme_font_size_override("font_size", 7)
	_style_small_btn(read_btn)
	read_btn.pressed.connect(func(): _open_story_detail(aname, idx))
	row.add_child(read_btn)

	var time_lbl = Label.new()
	time_lbl.text = _stamp_to_display(stamp)
	time_lbl.add_theme_font_size_override("font_size", 7)
	time_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	time_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(time_lbl)

func _stamp_to_display(stamp: String) -> String:
	# "YYYY-MM-DD_HH-MM" → "MM/DD HH:MM"
	var parts = stamp.split("_")
	if parts.size() != 2:
		return stamp
	var dp = parts[0].split("-")
	var tp = parts[1].split("-")
	if dp.size() >= 3 and tp.size() >= 2:
		return "%s/%s %s:%s" % [dp[1], dp[2], tp[0], tp[1]]
	return stamp

func _open_story_detail(aname: String, idx: int) -> void:
	var stories = _story_list.get(aname, [])
	if idx >= stories.size():
		return
	var story = stories[idx]

	var agent_idx = AGENT_NAMES.find(aname)
	var emoji = AGENT_EMOJIS[agent_idx] if agent_idx >= 0 else "📚"
	_detail_title_lbl.text = "%s %s · %s" % [emoji, aname, _stamp_to_display(story.get("stamp", ""))]
	_detail_body_lbl.text  = story.get("text", "（無內容）")

	_list_view.visible   = false
	_detail_view.visible = true

func _show_list_view() -> void:
	_detail_view.visible = false
	_list_view.visible   = true

func _close_panel() -> void:
	_panel.visible = false
	_panel_open    = false

func _close_all() -> void:
	_close_panel()
	_popup_open    = false
	_popup.visible = false

# ===== 故事生成 =====

func _generate_all_stories() -> void:
	if _generating:
		return
	_generating = true
	_done_count = 0
	_stories.clear()

	var date = Time.get_date_dict_from_system()
	var t    = Time.get_time_dict_from_system()
	_gen_stamp = "%04d-%02d-%02d_%02d-%02d" % [date.year, date.month, date.day, t.hour, t.minute]

	_story_btn.disabled = true
	_story_btn.text     = "⏳"

	generation_started.emit()   # 通知 world.gd 鎖定速度到 x1
	print("📚 [StoryGen] 平行生成四篇日誌（qwen2.5:1.5b，timeout=45s）…")

	for i in range(4):
		var aname = AGENT_NAMES[i]
		_stories[aname] = "LOADING"
		var body = JSON.stringify({
			"model":  OLLAMA_MODEL,
			"prompt": _build_story_prompt(i),
			"stream": false,
			"options": {"num_predict": 320, "temperature": 0.80}
		})
		var err = _http_pool[i].request(
			OLLAMA_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body
		)
		if err != OK:
			print("❌ [StoryGen] %s HTTP 請求失敗" % aname)
			_stories[aname] = "（請求失敗）"
			_done_count += 1
		else:
			print("📤 [StoryGen] %s 已送出（平行）" % aname)

func _build_story_prompt(agent_idx: int) -> String:
	var aname = AGENT_NAMES[agent_idx]
	var role  = AGENT_ROLES.get(aname, "村民")

	# ── 完整行程（全部列出）──
	var sched_lines: Array = []
	if agent_idx < _agents.size() and "schedule" in _agents[agent_idx]:
		for task in _agents[agent_idx].schedule:
			sched_lines.append("%s %s" % [_fmt_min(task.time), task.description])
	var sched_block = "\n".join(sched_lines) if sched_lines.size() > 0 else "日常作息"

	# ── 傍晚狀態（數值 → 感官語言）──
	var fatigue_phrase := "精神飽滿"
	var mood_phrase    := "心境平和"
	if agent_idx < _agents.size():
		var s  = _agents[agent_idx].get_status()
		var mv = float(s.get("mood_value", 70.0))
		var ft = float(s.get("fatigue",    0.0))
		if    ft > 75: fatigue_phrase = "渾身酸痛、筋疲力盡"
		elif  ft > 50: fatigue_phrase = "雙腿沉重、有些疲憊"
		elif  ft > 25: fatigue_phrase = "略感疲倦"
		if    mv > 80: mood_phrase    = "心滿意足、帶著微笑"
		elif  mv > 60: mood_phrase    = "心情尚好"
		elif  mv < 40: mood_phrase    = "心頭有些鬱悶"
		else:          mood_phrase    = "情緒平淡"

	# ── 今日對話片段（最多 2 句）──
	var conv_hint := ""
	if _conv_manager and "conversation_history" in _conv_manager:
		var hist: Array = _conv_manager.conversation_history
		var my_lines = hist.filter(func(e): return e.get("speaker","") == aname)
		if my_lines.size() > 0:
			var recent = my_lines.slice(max(0, my_lines.size() - 2))
			var quotes = recent.map(func(e): return "「" + e.get("content","").left(20) + "」")
			conv_hint = "途中曾說過：" + "、".join(quotes) + "。"

	# ── 結尾情緒提示 ──
	var ending_hint := "%s，%s入睡" % [fatigue_phrase, mood_phrase]

	# ── Prompt ──
	var prompt := ""
	prompt += "你是繁體中文短篇作家。請根據下面的行程，以第三人稱為角色寫一段敘事，要求：\n"
	prompt += "・一個完整段落，約 80 至 120 字，不分行，不加標題或說明\n"
	prompt += "・自然融入時間流動與具體活動，避免直接列時間點\n"
	prompt += "・文字有畫面感，結尾帶入角色的身體感受或心境\n\n"
	prompt += "角色：%s（%s）\n" % [aname, role]
	prompt += "今日行程：\n%s\n" % sched_block
	prompt += "結尾情緒提示：%s\n" % ending_hint
	if conv_hint != "":
		prompt += "對話素材（可自然融入，不要照抄）：%s\n" % conv_hint
	prompt += "\n"
	prompt += "【風格範例，請參考語氣，內容必須根據上面的行程重新創作】\n"
	prompt += "清晨六點，某伐木工在寒意中醒來，揉揉眼開始了新的一天。八點他便深入林間，"
	prompt += "揮汗砍下幾棵高杉，斧聲迴盪在靜謐的樹海裡。正午他靠著樹根吃了塊乾酪，聽著鳥鳴出神。"
	prompt += "傍晚收工時雙腿發沉，卻帶著踏實的滿足踏上歸途，在月色中推開了家門。\n\n"
	prompt += "請為 %s 輸出（只輸出故事段落）：" % aname
	return prompt

func _on_story_received(agent_idx: int, result: int, code: int, body: PackedByteArray) -> void:
	var aname = AGENT_NAMES[agent_idx]

	var story_text: String
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		story_text = "（生成失敗 result=%d code=%d）" % [result, code]
		print("❌ [StoryGen] %s 失敗 result=%d code=%d" % [aname, result, code])
	else:
		var text = body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(text) == OK and json.data is Dictionary:
			story_text = json.data.get("response", "（回應為空）").strip_edges()
		else:
			story_text = "（JSON 解析失敗）"

	_stories[aname] = story_text
	_done_count += 1
	print("✅ [StoryGen] %s 完成（%d/4）" % [aname, _done_count])

	if not story_text.begins_with("（"):
		_story_list[aname].push_front({"stamp": _gen_stamp, "text": story_text})
		if _panel_open and _list_view.visible and _selected_agent == aname:
			_rebuild_list_content(aname)

	if _done_count >= 4:
		_check_all_done()

func _check_all_done() -> void:
	_generating         = false
	_story_btn.disabled = false
	_story_btn.text     = "📚"
	generation_finished.emit()   # 通知 world.gd 恢復原速度
	print("🎉 [StoryGen] 所有日誌生成完畢，開始存檔")
	_save_all_stories()

func _save_all_stories() -> void:
	for aname in _stories:
		var story: String = _stories[aname]
		if story == "" or story == "LOADING" or story.begins_with("（"):
			continue

		var agent_abs = _stories_dir + "/" + aname
		DirAccess.make_dir_recursive_absolute(agent_abs)

		# 把故事文字拆成條目陣列（每行一條）存進 JSON
		var entries = story.split("\n", false)
		var payload = JSON.stringify({
			"agent":   aname,
			"stamp":   _gen_stamp,
			"entries": entries
		}, "\t")

		var fpath = agent_abs + "/story_%s.json" % _gen_stamp
		var file = FileAccess.open(fpath, FileAccess.WRITE)
		if file:
			file.store_string(payload)
			file.close()
			print("💾 [StoryGen] 已儲存：%s" % fpath)
		else:
			print("❌ [StoryGen] 儲存失敗（error %d）" % FileAccess.get_open_error())

# ===== 輔助 =====

func _fmt_min(minutes: int) -> String:
	return "%02d:%02d" % [minutes / 60, minutes % 60]

func _build_close_btn() -> Button:
	var btn = Button.new()
	btn.text = "✕"
	btn.custom_minimum_size = Vector2(14, 12)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 7)
	var s = StyleBoxFlat.new()
	s.bg_color     = Color(0.25, 0.12, 0.12, 0.9)
	s.border_color = Color(0.7, 0.3, 0.3)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 2;  s.content_margin_right  = 2
	s.content_margin_top  = 1;  s.content_margin_bottom = 1
	btn.add_theme_stylebox_override("normal", s)
	var sh = s.duplicate(); sh.bg_color = Color(0.45, 0.18, 0.18, 0.97)
	btn.add_theme_stylebox_override("hover", sh)
	btn.pressed.connect(_close_all)
	return btn

func _style_small_btn(btn: Button) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color     = Color(0.20, 0.20, 0.32)
	s.border_color = Color(0.40, 0.40, 0.65)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(0)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_stylebox_override("normal", s)
	var sh = s.duplicate(); sh.bg_color = Color(0.28, 0.28, 0.45)
	btn.add_theme_stylebox_override("hover", sh)
	var sp = s.duplicate(); sp.bg_color = Color(0.15, 0.15, 0.25)
	btn.add_theme_stylebox_override("pressed", sp)

func _round_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(0)
	return s
