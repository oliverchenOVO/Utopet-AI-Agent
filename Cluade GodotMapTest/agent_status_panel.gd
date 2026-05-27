# agent_status_panel.gd
# 右下角 📖 圓形按鈕 → 展開 2×2 格子的 Agent 生理狀態面板
# 每格：動畫鏡像（SubViewport）+ 飢餓 / 疲憊 / 心情 三條進度條
extends CanvasLayer

# ===== 顏色 =====
const HUNGER_COLOR  = Color(0.92, 0.32, 0.22)   # 紅橙
const FATIGUE_COLOR = Color(0.28, 0.55, 0.92)   # 藍
const MOOD_COLOR    = Color(0.28, 0.82, 0.44)   # 綠
const BAR_BG_COLOR  = Color(0.18, 0.18, 0.22, 0.9)
const CELL_BG_COLOR = Color(0.10, 0.10, 0.16, 0.95)
const PANEL_BG_COLOR = Color(0.07, 0.07, 0.12, 0.94)

# ===== 佈局尺寸 =====
const CELL_W    = 58     # 每格寬度
const CELL_H    = 68     # 每格高度
const SPRITE_SZ = 20     # SubViewport 邊長
const BAR_H     = 5      # 進度條高度
const BTN_SZ     = 20    # 圓形按鈕邊長
const BTN_MARGIN = 5     # 距螢幕邊緣距離
const SHIFT_LEFT = 30    # 向左偏移量（1.5 個按鈕寬）

# ===== Agent 資料 =====
var _agents: Array = []
var _real_sprites: Array = []  # 真實場景中的 AnimatedSprite2D

# ===== UI 節點 =====
var _root_ctrl: Control       # 全螢幕 Control，作為錨點基準
var _toggle_btn: Button
var _panel: PanelContainer
var _cells: Array = []        # [{mirror, hunger_bar, fatigue_bar, mood_bar}, ...]
var _panel_open: bool = false

const AGENT_NAMES  = ["Jack", "Mike", "Fin", "Buba"]
const AGENT_ICONS  = ["🪓",   "⛏️",  "🎣",  "🌾"]

# ===== 初始化 =====

func _ready() -> void:
	layer = 20
	_build_ui()

func setup(agent_list: Array) -> void:
	"""world.gd 在互動點設置完成後呼叫，傳入四個 agent 節點"""
	_agents = agent_list
	_real_sprites.clear()
	for a in agent_list:
		_real_sprites.append(a.get_node_or_null("AnimatedSprite2D"))

	# 把 SpriteFrames 資源連到鏡像 sprite（只需做一次）
	for i in range(min(_cells.size(), _real_sprites.size())):
		var real = _real_sprites[i]
		if real and real.sprite_frames:
			var mirror: AnimatedSprite2D = _cells[i]["mirror"]
			mirror.sprite_frames = real.sprite_frames
			mirror.play("Idle Front")

# ===== 建構 UI =====

func _build_ui() -> void:
	# 全螢幕根 Control（讓子節點能用 anchor 定位到角落）
	_root_ctrl = Control.new()
	_root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_ctrl)

	_build_toggle_button()
	_build_panel()

func _build_toggle_button() -> void:
	_toggle_btn = Button.new()
	_toggle_btn.text = "📖"
	_toggle_btn.custom_minimum_size = Vector2(BTN_SZ, BTN_SZ)
	_toggle_btn.focus_mode = Control.FOCUS_NONE

	# 右下角定位
	_toggle_btn.anchor_left   = 1.0
	_toggle_btn.anchor_right  = 1.0
	_toggle_btn.anchor_top    = 1.0
	_toggle_btn.anchor_bottom = 1.0
	_toggle_btn.offset_left   = -(BTN_SZ + BTN_MARGIN)
	_toggle_btn.offset_right  = -BTN_MARGIN
	_toggle_btn.offset_top    = -(BTN_SZ + BTN_MARGIN)
	_toggle_btn.offset_bottom = -BTN_MARGIN

	var radius = BTN_SZ / 2
	_toggle_btn.add_theme_stylebox_override("normal",  _round_style(Color(0.14, 0.14, 0.20, 0.93), Color(0.50, 0.50, 0.75), radius))
	_toggle_btn.add_theme_stylebox_override("hover",   _round_style(Color(0.20, 0.22, 0.32, 0.97), Color(0.70, 0.72, 0.95), radius))
	_toggle_btn.add_theme_stylebox_override("pressed", _round_style(Color(0.10, 0.10, 0.18, 0.97), Color(0.85, 0.85, 1.00), radius))
	_toggle_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toggle_btn.add_theme_font_size_override("font_size", 9)

	_toggle_btn.pressed.connect(_on_toggle)
	_root_ctrl.add_child(_toggle_btn)

func _build_panel() -> void:
	var panel_w = CELL_W * 2 + 14   # 2 欄 + gap + padding
	var panel_h = CELL_H * 2 + 14   # 2 列 + gap + padding

	_panel = PanelContainer.new()
	_panel.anchor_left   = 1.0
	_panel.anchor_right  = 1.0
	_panel.anchor_top    = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left   = -(panel_w + BTN_MARGIN + SHIFT_LEFT)
	_panel.offset_right  = -(BTN_MARGIN + SHIFT_LEFT)
	_panel.offset_top    = -(panel_h + BTN_SZ + BTN_MARGIN + 8)
	_panel.offset_bottom = -(BTN_SZ + BTN_MARGIN + 8)
	_panel.visible       = false

	var bg = StyleBoxFlat.new()
	bg.bg_color     = PANEL_BG_COLOR
	bg.border_color = Color(0.40, 0.40, 0.65)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(12)
	bg.content_margin_left   = 4
	bg.content_margin_right  = 4
	bg.content_margin_top    = 4
	bg.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", bg)
	_root_ctrl.add_child(_panel)

	# 頂層 VBox（標題列 + 2×2 格子）
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	_panel.add_child(vbox)

	# 標題列：右側 ✕ 關閉按鈕
	var title_row = HBoxContainer.new()
	vbox.add_child(title_row)

	var title_lbl = Label.new()
	title_lbl.text = "Agent 狀態面板"
	title_lbl.add_theme_font_size_override("font_size", 7)
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_lbl)

	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(14, 12)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 7)
	var cs = StyleBoxFlat.new()
	cs.bg_color = Color(0.25, 0.12, 0.12, 0.9)
	cs.border_color = Color(0.7, 0.3, 0.3)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(3)
	cs.set_content_margin_all(0)
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.add_theme_stylebox_override("normal", cs)
	var csh = cs.duplicate(); csh.bg_color = Color(0.45, 0.18, 0.18, 0.97)
	close_btn.add_theme_stylebox_override("hover", csh)
	close_btn.pressed.connect(_on_toggle)
	title_row.add_child(close_btn)

	# 2×2 GridContainer
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	for i in range(4):
		_cells.append(_build_cell(grid, i))

func _build_cell(parent: Control, idx: int) -> Dictionary:
	var aname = AGENT_NAMES[idx]
	var icon  = AGENT_ICONS[idx]

	# 外框 PanelContainer
	var cell_panel = PanelContainer.new()
	cell_panel.custom_minimum_size = Vector2(CELL_W, CELL_H)

	var cell_style = StyleBoxFlat.new()
	cell_style.bg_color     = CELL_BG_COLOR
	cell_style.border_color = Color(0.30, 0.30, 0.55)
	cell_style.set_border_width_all(1)
	cell_style.set_corner_radius_all(8)
	cell_style.content_margin_left   = 3
	cell_style.content_margin_right  = 3
	cell_style.content_margin_top    = 3
	cell_style.content_margin_bottom = 3
	cell_panel.add_theme_stylebox_override("panel", cell_style)
	parent.add_child(cell_panel)

	# 內部垂直排列
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	cell_panel.add_child(vbox)

	# 標題
	var title = Label.new()
	title.text                  = "%s %s" % [icon, aname]
	title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 6)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	vbox.add_child(title)

	# ── SubViewport：鏡像動畫 ──
	var svc = SubViewportContainer.new()
	svc.custom_minimum_size      = Vector2(CELL_W - 8, SPRITE_SZ + 2)
	svc.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	svc.stretch                  = true
	vbox.add_child(svc)

	var svp = SubViewport.new()
	svp.size                     = Vector2i(SPRITE_SZ, SPRITE_SZ + 2)
	svp.transparent_bg           = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svp.disable_3d               = true
	svc.add_child(svp)

	# 鏡像 AnimatedSprite2D（SpriteFrames 在 setup() 後才掛上）
	var mirror = AnimatedSprite2D.new()
	mirror.position = Vector2(SPRITE_SZ / 2.0, SPRITE_SZ / 2.0 + 1)
	svp.add_child(mirror)

	# ── 三條進度條 ──
	var bar_configs = [
		{"key": "hunger",  "label": "🍽️ 飢餓", "color": HUNGER_COLOR,  "tooltip": "飢餓值（越高越餓）"},
		{"key": "fatigue", "label": "😴 疲憊", "color": FATIGUE_COLOR, "tooltip": "疲憊值（越高越累）"},
		{"key": "mood",    "label": "😊 心情", "color": MOOD_COLOR,    "tooltip": "心情值（越高越好）"},
	]
	var bars: Dictionary = {}

	for cfg in bar_configs:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)

		var lbl = Label.new()
		lbl.text = cfg["label"]
		lbl.add_theme_font_size_override("font_size", 6)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		lbl.custom_minimum_size = Vector2(27, 0)
		row.add_child(lbl)

		var bar = ProgressBar.new()
		bar.min_value             = 0.0
		bar.max_value             = 100.0
		bar.value                 = 50.0
		bar.show_percentage       = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size   = Vector2(0, BAR_H)
		bar.tooltip_text          = cfg["tooltip"]

		var fill_s = StyleBoxFlat.new()
		fill_s.bg_color = cfg["color"]
		fill_s.set_corner_radius_all(4)

		var bg_s = StyleBoxFlat.new()
		bg_s.bg_color = BAR_BG_COLOR
		bg_s.set_corner_radius_all(4)

		bar.add_theme_stylebox_override("fill",       fill_s)
		bar.add_theme_stylebox_override("background", bg_s)
		row.add_child(bar)
		bars[cfg["key"]] = bar

	return {
		"mirror":      mirror,
		"hunger_bar":  bars["hunger"],
		"fatigue_bar": bars["fatigue"],
		"mood_bar":    bars["mood"],
	}

# ===== 每幀同步 =====

func _process(_delta: float) -> void:
	if not _panel_open or _agents.is_empty():
		return
	for i in range(min(_agents.size(), _cells.size())):
		_sync_cell(i)

func _sync_cell(i: int) -> void:
	var agent = _agents[i]
	var cell  = _cells[i]
	var mirror: AnimatedSprite2D = cell["mirror"]

	# 同步動畫（僅在 sprite_frames 就緒後）
	if i < _real_sprites.size() and _real_sprites[i] and mirror.sprite_frames:
		var real: AnimatedSprite2D = _real_sprites[i]
		# 切動畫
		if mirror.animation != real.animation:
			if mirror.sprite_frames.has_animation(real.animation):
				mirror.play(real.animation)
		# 同步幀、翻轉、旋轉
		mirror.frame            = real.frame
		mirror.flip_h           = real.flip_h
		mirror.rotation_degrees = real.rotation_degrees

	# 同步數值條
	var s = agent.get_status()
	cell["hunger_bar"].value  = s.get("hunger",     0.0)
	cell["fatigue_bar"].value = s.get("fatigue",    0.0)
	cell["mood_bar"].value    = s.get("mood_value", 70.0)

# ===== 切換顯示 =====

func _on_toggle() -> void:
	_panel_open = not _panel_open
	_panel.visible = _panel_open

# ===== 輔助 =====

func _round_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(0)
	return s
