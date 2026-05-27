# terminal_window.gd
# 系統輸出終端視窗
# 與 agent_status_panel 等同一架構：root_ctrl PRESET_FULL_RECT → 子節點用 Godot 像素定位
extends CanvasLayer

# ===== 視窗位置（佔 CanvasLayer 空間的百分比）=====
# CanvasLayer 空間 = Viewport 大小（336×256）
# 下方中央區塊，左 28%~右 72%，上 73%~下 97%
const WIN_FRAC_L    : float = 0.48   # 右移半個視窗寬（原 0.28 + 0.22）
const WIN_FRAC_R    : float = 0.92   # 右移半個視窗寬（原 0.72 + 0.22）
const WIN_FRAC_T    : float = 0.73
const WIN_FRAC_B    : float = 0.97
const HANDLE_FRAC_H : float = 0.04   # 把手高：佔 root 高度 4%
const TWEEN_T       : float = 0.38

# ===== 視覺配置 =====
const COLOR_BG     := Color(0.04, 0.05, 0.09, 0.93)
const COLOR_BORDER := Color(0.28, 0.42, 0.58, 1.00)
const COLOR_HANDLE := Color(0.18, 0.23, 0.34, 0.97)
const COLOR_TEXT   := Color(0.76, 0.91, 0.76, 1.00)
const COLOR_ARROW  := Color(0.90, 0.92, 1.00, 1.00)
const MAX_LINES    : int = 300

# ===== 執行期計算（_ready 填入）=====
var _root_w  : float = 336.0
var _root_h  : float = 256.0
var _win_pos : Vector2
var _win_size: Vector2
var _hdl_h   : float   # 把手高（像素）

var _panel_open_y  : float
var _panel_close_y : float
var _hdl_open_y    : float
var _hdl_close_y   : float

# ===== 節點引用 =====
var _root_ctrl : Control
var _handle    : Panel
var _arrow     : Label
var _panel     : Panel
var _rtl       : RichTextLabel
var _tween     : Tween

var _collapsed  : bool = false
var _line_count : int  = 0

# ===== 初始化 =====

func _ready() -> void:
	layer = 15

	# 建立全屏根控制（與其他 UI 面板相同架構）
	_root_ctrl = Control.new()
	_root_ctrl.name = "RootCtrl"
	_root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_ctrl)

	# 等待佈局計算，讓 size 確實填入
	await get_tree().process_frame
	await get_tree().process_frame

	_root_w = _root_ctrl.size.x if _root_ctrl.size.x > 0.0 else 336.0
	_root_h = _root_ctrl.size.y if _root_ctrl.size.y > 0.0 else 256.0

	_win_pos  = Vector2(_root_w * WIN_FRAC_L, _root_h * WIN_FRAC_T)
	_win_size = Vector2(_root_w * (WIN_FRAC_R - WIN_FRAC_L),
						_root_h * (WIN_FRAC_B - WIN_FRAC_T))
	_hdl_h = _root_h * HANDLE_FRAC_H

	# 展開：面板底部 = 畫面底部（_panel_close_y 的舊位置成為新展開位置）
	_panel_open_y  = _root_h - _win_size.y   # 面板底貼齊畫面底
	_hdl_open_y    = _root_h - _win_size.y - _hdl_h   # 把手緊貼面板上方

	# 收縮：面板完全沉出畫面，只剩把手露出底部
	_panel_close_y = _root_h                  # 面板頂 = 畫面底，完全不可見
	_hdl_close_y   = _root_h - _hdl_h        # 把手底 = 畫面底，剛好露出

	_build_panel()
	_build_handle()

	print("🖥️  [TerminalWindow] root=(%.0f×%.0f)  win=(%.0f,%.0f) %.0f×%.0f  layer=%d" % [
		_root_w, _root_h, _win_pos.x, _win_pos.y, _win_size.x, _win_size.y, layer])

# ===== UI 建構 =====

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.name     = "TerminalPanel"
	_panel.position = Vector2(_win_pos.x, _panel_open_y)
	_panel.size     = _win_size
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bw : int = maxi(1, int(_root_h * 0.006))   # 邊框粗細
	var cr : int = maxi(2, int(_root_h * 0.014))   # 圓角半徑

	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_BG
	s.border_color = COLOR_BORDER
	s.set_border_width_all(bw)
	s.corner_radius_bottom_left  = cr
	s.corner_radius_bottom_right = cr
	_panel.add_theme_stylebox_override("panel", s)

	var mg : int = maxi(2, int(_root_h * 0.010))   # 內邊距
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.add_theme_constant_override("margin_left",   mg)
	mc.add_theme_constant_override("margin_right",  mg)
	mc.add_theme_constant_override("margin_top",    mg)
	mc.add_theme_constant_override("margin_bottom", mg)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(mc)

	var fs : int = maxi(4, int(_root_h * 0.022))   # 字型大小（root 高 2.2%）

	_rtl = RichTextLabel.new()
	_rtl.name = "Output"
	_rtl.bbcode_enabled   = true
	_rtl.scroll_following = true
	_rtl.fit_content      = false
	_rtl.mouse_filter     = Control.MOUSE_FILTER_PASS
	_rtl.add_theme_font_size_override("normal_font_size", fs)
	_rtl.add_theme_color_override("default_color", COLOR_TEXT)
	mc.add_child(_rtl)

	_root_ctrl.add_child(_panel)

func _build_handle() -> void:
	_handle = Panel.new()
	_handle.name     = "Handle"
	_handle.position = Vector2(_win_pos.x, _hdl_open_y)   # 展開初始位置
	_handle.size     = Vector2(_win_size.x, _hdl_h)
	_handle.mouse_filter = Control.MOUSE_FILTER_STOP

	var bw : int = maxi(1, int(_root_h * 0.006))
	var cr : int = maxi(2, int(_root_h * 0.014))

	var s := StyleBoxFlat.new()
	s.bg_color = COLOR_HANDLE
	s.border_color = COLOR_BORDER
	s.set_border_width_all(bw)
	s.corner_radius_top_left  = cr
	s.corner_radius_top_right = cr
	_handle.add_theme_stylebox_override("panel", s)

	var arr_fs : int = maxi(4, int(_hdl_h * 0.65))

	_arrow = Label.new()
	_arrow.text = "▼"
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_arrow.add_theme_font_size_override("font_size", arr_fs)
	_arrow.add_theme_color_override("font_color", COLOR_ARROW)
	_arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_handle.add_child(_arrow)

	_handle.gui_input.connect(_on_handle_input)
	_root_ctrl.add_child(_handle)

# ===== 互動邏輯 =====

func _on_handle_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed):
		return
	if _collapsed:
		_do_expand()
	else:
		_do_collapse()

func _do_collapse() -> void:
	_collapsed = true
	_arrow.text = "▲"
	_animate(_panel_close_y, _hdl_close_y)

func _do_expand() -> void:
	_collapsed = false
	_arrow.text = "▼"
	_animate(_panel_open_y, _hdl_open_y)

func _animate(panel_y: float, handle_y: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_panel,  "position:y", panel_y,  TWEEN_T)
	_tween.parallel().tween_property(_handle, "position:y", handle_y, TWEEN_T)

# ===== 公開 API =====

func log_text(text: String) -> void:
	if not _rtl:
		return
	_line_count += 1
	if _line_count > MAX_LINES:
		_rtl.clear()
		_line_count = 1
	_rtl.append_text(text + "\n")

func log_info(text: String)  -> void: log_text("[color=#8ec88e]%s[/color]" % text)
func log_warn(text: String)  -> void: log_text("[color=#e8d06a]⚠ %s[/color]" % text)
func log_error(text: String) -> void: log_text("[color=#e86a6a]✗ %s[/color]" % text)

func clear() -> void:
	if _rtl:
		_rtl.clear()
		_line_count = 0

func set_collapsed(value: bool) -> void:
	_collapsed = value
	_arrow.text = "▲" if value else "▼"
	_panel.position.y  = _panel_close_y if value else _panel_open_y
	_handle.position.y = _hdl_close_y   if value else _hdl_open_y
