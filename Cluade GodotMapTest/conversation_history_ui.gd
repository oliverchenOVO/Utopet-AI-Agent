# conversation_history_ui.gd
# 對話歷史紀錄 UI：列表視圖 ↔ 聊天室詳細視圖
# 透過 agent_conversation_manager 的三個信號驅動，無需主動 poll
extends CanvasLayer

# ===== 佈局常數（與 agent_status_panel 對齊）=====
const BTN_SZ     = 20
const BTN_MARGIN = 5
const BTN_GAP    = 4       # 本按鈕與下方 📖 按鈕的間距
const SHIFT_LEFT = 30      # 向左偏移量（1.5 個按鈕寬）
const PANEL_W    = 210
const PANEL_H    = 155
const AVATAR_SZ  = 16      # 頭像方塊邊長

# ===== 顏色（與 conversation_manager 一致）=====
const AGENT_COLORS = {
	"Jack": Color(0.9,  0.5,  0.1,  1.0),
	"Mike": Color(0.6,  0.6,  0.7,  1.0),
	"Fin":  Color(0.2,  0.6,  0.9,  1.0),
	"Buba": Color(0.2,  0.7,  0.3,  1.0),
}
const DEFAULT_COLOR = Color(0.6, 0.6, 0.6)
const PANEL_BG    = Color(0.07, 0.07, 0.12, 0.94)
const BUBBLE_BG   = Color(0.14, 0.14, 0.22, 0.95)
const CELL_BG     = Color(0.10, 0.10, 0.16, 0.95)

# ===== 資料模型 =====
# session: {
#   id: int, agents: [str, str], start_time_str: str,
#   messages: [{speaker, text, time_str}], is_active: bool
# }
var _sessions: Array        = []
var _active_session_id: int = -1

# ===== UI 節點 =====
var _root_ctrl:   Control
var _toggle_btn:  Button
var _panel:       PanelContainer

# 列表視圖
var _list_view:    VBoxContainer
var _list_scroll:  ScrollContainer
var _list_content: VBoxContainer

# 詳細視圖
var _detail_view:         VBoxContainer
var _detail_title_label:  Label
var _detail_scroll:       ScrollContainer
var _detail_content:      VBoxContainer
var _detail_last_speaker: String = ""   # 用於判斷連續發言
var _current_detail_sid:  int    = -1

var _panel_open: bool = false

# ===== 初始化 =====

func _ready() -> void:
	layer = 21
	_build_ui()

func setup(conv_manager: Node) -> void:
	"""由 world.gd 在 conversation_manager 建立後呼叫"""
	if not conv_manager:
		return
	conv_manager.conversation_started.connect(_on_conversation_started)
	conv_manager.conversation_ended.connect(_on_conversation_ended)
	conv_manager.dialogue_line_displayed.connect(_on_dialogue_line)
	print("📜 [HistoryUI] 已連接對話信號")

# ===== 信號處理 =====

func _on_conversation_started(a1: String, a2: String) -> void:
	var session = {
		"id":             _sessions.size(),
		"agents":         [a1, a2],
		"start_time_str": _get_game_time(),
		"messages":       [],
		"is_active":      true
	}
	_sessions.append(session)
	_active_session_id = session["id"]
	_append_list_entry(session)

func _on_dialogue_line(speaker: String, text: String) -> void:
	if _active_session_id < 0 or _active_session_id >= _sessions.size():
		return
	var session = _sessions[_active_session_id]
	var msg = {"speaker": speaker, "text": text, "time_str": _get_game_time()}
	session["messages"].append(msg)

	# 若詳細視圖正在顯示此對話，即時追加訊息
	if _current_detail_sid == _active_session_id:
		var is_consec = (speaker == _detail_last_speaker and _detail_last_speaker != "")
		_append_message_row(msg, is_consec)
		_detail_last_speaker = speaker
		_scroll_detail_bottom()

func _on_conversation_ended() -> void:
	if _active_session_id >= 0 and _active_session_id < _sessions.size():
		_sessions[_active_session_id]["is_active"] = false
	_active_session_id = -1

# ===== 建構 UI =====

func _build_ui() -> void:
	_root_ctrl = Control.new()
	_root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_ctrl)
	_build_toggle_button()
	_build_panel()

func _build_toggle_button() -> void:
	_toggle_btn = Button.new()
	_toggle_btn.text = "💬"
	_toggle_btn.custom_minimum_size = Vector2(BTN_SZ, BTN_SZ)
	_toggle_btn.focus_mode = Control.FOCUS_NONE

	# 右下角，位於 📖 按鈕上方
	_toggle_btn.anchor_left   = 1.0
	_toggle_btn.anchor_right  = 1.0
	_toggle_btn.anchor_top    = 1.0
	_toggle_btn.anchor_bottom = 1.0
	_toggle_btn.offset_left   = -(BTN_SZ + BTN_MARGIN)
	_toggle_btn.offset_right  = -BTN_MARGIN
	_toggle_btn.offset_bottom = -(BTN_SZ + BTN_MARGIN + BTN_GAP)
	_toggle_btn.offset_top    = -(BTN_SZ * 2 + BTN_MARGIN + BTN_GAP)

	var r = BTN_SZ / 2
	_toggle_btn.add_theme_stylebox_override("normal",  _round_style(Color(0.14, 0.14, 0.20, 0.93), Color(0.50, 0.50, 0.75), r))
	_toggle_btn.add_theme_stylebox_override("hover",   _round_style(Color(0.20, 0.22, 0.32, 0.97), Color(0.70, 0.72, 0.95), r))
	_toggle_btn.add_theme_stylebox_override("pressed", _round_style(Color(0.10, 0.10, 0.18, 0.97), Color(0.85, 0.85, 1.00), r))
	_toggle_btn.add_theme_font_size_override("font_size", 9)
	_toggle_btn.pressed.connect(_on_toggle)
	_root_ctrl.add_child(_toggle_btn)

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left   = 1.0
	_panel.anchor_right  = 1.0
	_panel.anchor_top    = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left   = -(PANEL_W + BTN_MARGIN + SHIFT_LEFT)
	_panel.offset_right  = -(BTN_MARGIN + SHIFT_LEFT)
	# 面板底部對齊歷史按鈕下緣
	_panel.offset_bottom = -(BTN_SZ + BTN_MARGIN + BTN_GAP)
	_panel.offset_top    = -(PANEL_H + BTN_SZ + BTN_MARGIN + BTN_GAP)
	_panel.visible       = false
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)

	var bg = StyleBoxFlat.new()
	bg.bg_color     = PANEL_BG
	bg.border_color = Color(0.40, 0.40, 0.65)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	bg.content_margin_left   = 6
	bg.content_margin_right  = 6
	bg.content_margin_top    = 6
	bg.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", bg)
	_root_ctrl.add_child(_panel)

	var wrapper = VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 0)
	_panel.add_child(wrapper)

	_build_list_view(wrapper)
	_build_detail_view(wrapper)

	_list_view.visible   = true
	_detail_view.visible = false

# ===== 列表視圖 =====

func _build_list_view(parent: Control) -> void:
	_list_view = VBoxContainer.new()
	_list_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_view.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_list_view.add_theme_constant_override("separation", 4)
	parent.add_child(_list_view)

	var list_header = HBoxContainer.new()
	list_header.add_theme_constant_override("separation", 4)
	_list_view.add_child(list_header)

	var title_lbl = Label.new()
	title_lbl.text = "📜 對話紀錄"
	title_lbl.add_theme_font_size_override("font_size", 8)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_header.add_child(title_lbl)

	list_header.add_child(_build_close_btn())

	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_list_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_view.add_child(_list_scroll)

	_list_content = VBoxContainer.new()
	_list_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_content.add_theme_constant_override("separation", 3)
	_list_scroll.add_child(_list_content)

	var empty_lbl = Label.new()
	empty_lbl.name = "EmptyLabel"
	empty_lbl.text = "（尚無對話紀錄）"
	empty_lbl.add_theme_font_size_override("font_size", 7)
	empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list_content.add_child(empty_lbl)

func _append_list_entry(session: Dictionary) -> void:
	# 隱藏空白提示
	var empty = _list_content.get_node_or_null("EmptyLabel")
	if empty:
		empty.visible = false

	var entry_bg = PanelContainer.new()
	var es = StyleBoxFlat.new()
	es.bg_color     = CELL_BG
	es.border_color = Color(0.25, 0.25, 0.45)
	es.set_border_width_all(1)
	es.set_corner_radius_all(4)
	es.content_margin_left   = 4
	es.content_margin_right  = 4
	es.content_margin_top    = 3
	es.content_margin_bottom = 3
	entry_bg.add_theme_stylebox_override("panel", es)
	_list_content.add_child(entry_bg)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	entry_bg.add_child(row)

	# 「詳細」按鈕
	var detail_btn = Button.new()
	detail_btn.text = "詳細"
	detail_btn.custom_minimum_size = Vector2(28, 14)
	detail_btn.focus_mode = Control.FOCUS_NONE
	detail_btn.add_theme_font_size_override("font_size", 7)
	_style_small_btn(detail_btn)
	var sid = session["id"]
	detail_btn.pressed.connect(func(): _open_detail(sid))
	row.add_child(detail_btn)

	# 參與者標題
	var agents_lbl = Label.new()
	agents_lbl.text = _session_title(session)
	agents_lbl.add_theme_font_size_override("font_size", 7)
	agents_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	agents_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agents_lbl.clip_contents = true
	row.add_child(agents_lbl)

	# 時間標籤
	var time_lbl = Label.new()
	time_lbl.text = session["start_time_str"]
	time_lbl.add_theme_font_size_override("font_size", 7)
	time_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	row.add_child(time_lbl)

	# 滾到列表底部
	await get_tree().process_frame
	_list_scroll.scroll_vertical = _list_scroll.get_v_scroll_bar().max_value

# ===== 詳細視圖 =====

func _build_detail_view(parent: Control) -> void:
	_detail_view = VBoxContainer.new()
	_detail_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_view.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_detail_view.add_theme_constant_override("separation", 4)
	parent.add_child(_detail_view)

	# 標題列：返回按鈕 + 標題
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

	_detail_title_label = Label.new()
	_detail_title_label.add_theme_font_size_override("font_size", 8)
	_detail_title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_detail_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_detail_title_label)

	header.add_child(_build_close_btn())

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_view.add_child(_detail_scroll)

	_detail_content = VBoxContainer.new()
	_detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.add_theme_constant_override("separation", 2)
	_detail_scroll.add_child(_detail_content)

func _open_detail(sid: int) -> void:
	if sid >= _sessions.size():
		return
	var session = _sessions[sid]
	_current_detail_sid  = sid
	_detail_last_speaker = ""

	# 清空舊內容
	for child in _detail_content.get_children():
		child.queue_free()

	_detail_title_label.text = _session_title(session)

	# 重建所有已有訊息，帶連續發言判斷
	var prev_speaker = ""
	for msg in session["messages"]:
		var is_consec = (msg["speaker"] == prev_speaker and prev_speaker != "")
		_append_message_row(msg, is_consec)
		prev_speaker = msg["speaker"]
	_detail_last_speaker = prev_speaker

	_list_view.visible   = false
	_detail_view.visible = true

	await get_tree().process_frame
	_scroll_detail_bottom()

func _show_list_view() -> void:
	_current_detail_sid  = -1
	_detail_last_speaker = ""
	_detail_view.visible = false
	_list_view.visible   = true

# 建立單句對話列
# is_consecutive = true → 隱藏頭像，用等寬空白佔位
func _append_message_row(msg: Dictionary, is_consecutive: bool) -> void:
	var speaker = msg["speaker"]
	var text    = msg["text"]

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_content.add_child(row)

	# 左側：頭像 or 等寬空白
	if is_consecutive:
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(AVATAR_SZ, AVATAR_SZ)
		row.add_child(spacer)
	else:
		row.add_child(_build_avatar(speaker))

	# 右側：對話氣泡
	var bubble = PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bs = StyleBoxFlat.new()
	bs.bg_color     = BUBBLE_BG
	bs.border_color = AGENT_COLORS.get(speaker, DEFAULT_COLOR)
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(4)
	if not is_consecutive:
		bs.corner_radius_top_left = 1   # 靠近頭像側角更小
	bs.content_margin_left   = 4
	bs.content_margin_right  = 4
	bs.content_margin_top    = 2
	bs.content_margin_bottom = 2
	bubble.add_theme_stylebox_override("panel", bs)
	row.add_child(bubble)

	var lbl = Label.new()
	lbl.text           = text
	lbl.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	bubble.add_child(lbl)

# 彩色頭像方塊（以 Agent 名稱首字母為標籤）
func _build_avatar(agent_name: String) -> Control:
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(AVATAR_SZ, AVATAR_SZ)

	var s = StyleBoxFlat.new()
	s.bg_color = AGENT_COLORS.get(agent_name, DEFAULT_COLOR)
	s.set_corner_radius_all(3)
	s.content_margin_left   = 0
	s.content_margin_right  = 0
	s.content_margin_top    = 0
	s.content_margin_bottom = 0
	container.add_theme_stylebox_override("panel", s)

	var lbl = Label.new()
	lbl.text               = agent_name.left(1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	container.add_child(lbl)

	return container

func _scroll_detail_bottom() -> void:
	await get_tree().process_frame
	_detail_scroll.scroll_vertical = _detail_scroll.get_v_scroll_bar().max_value

# ===== 切換面板 =====

func _on_toggle() -> void:
	_panel_open = not _panel_open
	_panel.visible = _panel_open

# ===== 輔助 =====

func _get_game_time() -> String:
	var p = get_parent()
	if p and "sim_clock_minutes" in p:
		var m: int = p.sim_clock_minutes
		return "%02d:%02d" % [m / 60, m % 60]
	return "--:--"

func _session_title(session: Dictionary) -> String:
	var ag: Array = session["agents"]
	if ag.size() >= 2:
		return "%s 💬 %s" % [ag[0], ag[1]]
	return "對話"

func _style_small_btn(btn: Button) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color     = Color(0.20, 0.20, 0.32)
	s.border_color = Color(0.40, 0.40, 0.65)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(0)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_stylebox_override("normal", s)

	var sh = s.duplicate()
	sh.bg_color = Color(0.28, 0.28, 0.45)
	btn.add_theme_stylebox_override("hover", sh)

	var sp = s.duplicate()
	sp.bg_color = Color(0.15, 0.15, 0.25)
	btn.add_theme_stylebox_override("pressed", sp)

func _build_close_btn() -> Button:
	var btn = Button.new()
	btn.text = "✕"
	btn.custom_minimum_size = Vector2(14, 12)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 7)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.25, 0.12, 0.12, 0.9)
	s.border_color = Color(0.7, 0.3, 0.3)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(0)
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_stylebox_override("normal", s)
	var sh = s.duplicate(); sh.bg_color = Color(0.45, 0.18, 0.18, 0.97)
	btn.add_theme_stylebox_override("hover", sh)
	btn.pressed.connect(_on_toggle)
	return btn

func _round_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(0)
	return s
