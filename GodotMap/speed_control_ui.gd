# speed_control_ui.gd
# 左下角 ⚙️ 按鈕 → 展開速度選擇面板，與右下角 Agent 狀態面板同高
extends CanvasLayer

# ===== 佈局常數（與 agent_status_panel 一致）=====
const BTN_SZ     = 20
const BTN_MARGIN = 5

const SPEEDS       = [1.0, 2.0, 5.0, 10.0, 30.0]
const SPEED_LABELS = ["x1", "x2", "x5", "x10", "x30"]

# 速度按鈕佈局（2 欄 × 3 列 grid）
const PBTN_W  = 28   # 每個速度按鈕的寬
const PBTN_H  = 14   # 每個速度按鈕的高
const PGAP    = 2    # 按鈕間距

# ===== UI 節點 =====
var _root_ctrl: Control
var _toggle_btn: Button
var _panel: PanelContainer
var _vbox: VBoxContainer
var _speed_btns: Array = []
var _pause_btn: Button
var _panel_open: bool = false
var _tween: Tween = null

# 面板的真實幾何（在 _build_panel 時固定，不受 tween 影響）
var _panel_true_h: float = 0.0
var _panel_true_w: float = 0.0

# ===== World 引用 =====
var _world: Node = null

# ===== 初始化 =====

func _ready() -> void:
	layer = 20   # 與 Agent 狀態面板同層
	_build_ui()

func setup(world_node: Node) -> void:
	_world = world_node

# ===== UI 建構 =====

func _build_ui() -> void:
	_root_ctrl = Control.new()
	_root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_ctrl)
	_build_toggle_button()
	_build_panel()

func _build_toggle_button() -> void:
	_toggle_btn = Button.new()
	_toggle_btn.text      = "⚙️"
	_toggle_btn.custom_minimum_size = Vector2(BTN_SZ, BTN_SZ)
	_toggle_btn.focus_mode = Control.FOCUS_NONE

	# 左下角，與右下角按鈕同高
	_toggle_btn.anchor_left   = 0.0
	_toggle_btn.anchor_right  = 0.0
	_toggle_btn.anchor_top    = 1.0
	_toggle_btn.anchor_bottom = 1.0
	_toggle_btn.offset_left   = BTN_MARGIN
	_toggle_btn.offset_right  = BTN_SZ + BTN_MARGIN
	_toggle_btn.offset_top    = -(BTN_SZ + BTN_MARGIN)
	_toggle_btn.offset_bottom = -BTN_MARGIN

	var r = BTN_SZ / 2
	_toggle_btn.add_theme_stylebox_override("normal",  _round_style(Color(0.14, 0.14, 0.20, 0.93), Color(0.50, 0.50, 0.75), r))
	_toggle_btn.add_theme_stylebox_override("hover",   _round_style(Color(0.20, 0.22, 0.32, 0.97), Color(0.70, 0.72, 0.95), r))
	_toggle_btn.add_theme_stylebox_override("pressed", _round_style(Color(0.10, 0.10, 0.18, 0.97), Color(0.85, 0.85, 1.00), r))
	_toggle_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toggle_btn.add_theme_font_size_override("font_size", 9)
	_toggle_btn.pressed.connect(_on_toggle)
	_root_ctrl.add_child(_toggle_btn)

func _build_panel() -> void:
	# Grid 2欄×3列：[x1][x2] / [x5][x10] / [x30][⏸]
	# 最後一列右欄放暫停按鈕
	const COLS = 2
	const ROWS = 3
	var panel_w = COLS * PBTN_W + (COLS - 1) * PGAP + 8
	var panel_h = ROWS * PBTN_H + (ROWS - 1) * PGAP + 8

	_panel_true_w = float(panel_w)
	_panel_true_h = float(panel_h)

	_panel = PanelContainer.new()
	_panel.anchor_left   = 0.0
	_panel.anchor_right  = 0.0
	_panel.anchor_top    = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left   = BTN_MARGIN
	_panel.offset_right  = BTN_MARGIN + panel_w
	_panel.offset_top    = -(BTN_SZ + BTN_MARGIN + panel_h + 4)
	_panel.offset_bottom = -(BTN_SZ + BTN_MARGIN + 4)
	_panel.visible       = false

	var bg = StyleBoxFlat.new()
	bg.bg_color     = Color(0.07, 0.07, 0.12, 0.94)
	bg.border_color = Color(0.40, 0.40, 0.65)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	bg.content_margin_left   = 4
	bg.content_margin_right  = 4
	bg.content_margin_top    = 4
	bg.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", bg)

	# 外層容器（margin 已由 content_margin 處理）
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(margin)

	var grid = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", PGAP)
	grid.add_theme_constant_override("v_separation", PGAP)
	margin.add_child(grid)

	# 速度按鈕：x1 x2 / x5 x10 / x30 [pause]
	for i in range(SPEEDS.size()):
		var btn = _make_speed_btn(SPEED_LABELS[i], SPEEDS[i])
		grid.add_child(btn)
		_speed_btns.append(btn)

	# 暫停按鈕（接在 x30 後面，填入 grid 第 6 格）
	_pause_btn = _make_btn("⏸", PBTN_W, PBTN_H)
	_pause_btn.pressed.connect(_toggle_pause)
	grid.add_child(_pause_btn)

	_root_ctrl.add_child(_panel)
	_update_styles()

func _make_speed_btn(label: String, spd: float) -> Button:
	var btn = _make_btn(label, PBTN_W, PBTN_H)
	btn.pressed.connect(func(): _set_speed(spd))
	return btn

func _make_btn(label: String, w: int, h: int) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(w, h)
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_size_override("font_size", 9)
	return btn

# ===== 行為 =====

func _place_panel() -> void:
	var vp        = get_viewport().get_visible_rect().size
	var btn_top_y = vp.y - BTN_SZ - BTN_MARGIN
	var p_bottom  = btn_top_y - 4.0
	var p_top     = p_bottom - _panel_true_h
	if p_top < 2.0:
		p_top    = 2.0
		p_bottom = p_top + _panel_true_h
	# anchor_top = 1.0 → offsets are relative to the bottom edge of the viewport
	_panel.offset_top    = p_top    - vp.y
	_panel.offset_bottom = p_bottom - vp.y
	_panel.offset_left   = float(BTN_MARGIN)
	_panel.offset_right  = float(BTN_MARGIN) + _panel_true_w

func _on_toggle() -> void:
	_panel_open = not _panel_open

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)

	if _panel_open:
		_update_styles()
		_place_panel()                          # 先定位到正確位置（根據當前視口）
		var open_top = _panel.offset_top        # _place_panel 已算好正確的 top
		_panel.offset_top = _panel.offset_bottom - 2.0  # 從壓縮態開始
		_panel.visible = true
		_tween.tween_property(_panel, "offset_top", open_top, 0.18)
	else:
		var collapsed_top = _panel.offset_bottom - 2.0
		_tween.tween_property(_panel, "offset_top", collapsed_top, 0.14)
		_tween.tween_callback(func(): _panel.visible = false)

func _set_speed(spd: float) -> void:
	if not _world:
		return
	_world.time_speed       = spd
	_world.auto_advance_time = true
	_update_styles()
	print("⏩ 速度: x%.0f" % spd)

func _toggle_pause() -> void:
	if not _world:
		return
	_world.auto_advance_time = not _world.auto_advance_time
	_update_styles()
	print("⏸️ 時間%s" % ("恢復" if _world.auto_advance_time else "暫停"))

func _update_styles() -> void:
	if not _world:
		return

	for i in range(_speed_btns.size()):
		var btn: Button = _speed_btns[i]
		var active = (_world.time_speed == SPEEDS[i]) and _world.auto_advance_time
		if active:
			btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			btn.add_theme_stylebox_override("normal",
				_pill_style(Color(0.28, 0.22, 0.04, 0.95), Color(0.75, 0.62, 0.18)))
		else:
			btn.remove_theme_color_override("font_color")
			btn.add_theme_stylebox_override("normal",
				_pill_style(Color(0.14, 0.14, 0.20, 0.85), Color(0.40, 0.40, 0.60)))

	var paused = not _world.auto_advance_time
	_pause_btn.text = "▶" if paused else "⏸"
	if paused:
		_pause_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		_pause_btn.add_theme_stylebox_override("normal",
			_pill_style(Color(0.05, 0.22, 0.08, 0.95), Color(0.28, 0.70, 0.30)))
	else:
		_pause_btn.remove_theme_color_override("font_color")
		_pause_btn.add_theme_stylebox_override("normal",
			_pill_style(Color(0.14, 0.14, 0.20, 0.85), Color(0.40, 0.40, 0.60)))

func _process(_delta: float) -> void:
	# 面板開著時保持按鈕樣式與 world 狀態同步（例如鍵盤 T/P 也會改變速度）
	if _panel_open and _world:
		_update_styles()

# ===== StyleBox 工廠 =====

func _round_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(0)
	return s

func _pill_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(0)
	return s
