# setting.gd
extends Panel

@onready var volume_slider = $Panel/VBoxContainer/設定選項/HSlider
@onready var ai_checkbox = $Panel/VBoxContainer/設定選項/CheckBox

func _ready():
	# Panel 不支援 set_title，如果需要標題，請在場景中加一個 Label
	
	# 設定大小 (Control 節點用法)
	custom_minimum_size = Vector2(400, 300)
	
	# 初始化 UI 狀態
	volume_slider.value = Global.volume_level
	ai_checkbox.button_pressed = Global.is_ai_enabled

func _on_ok_pressed():
	self.hide()

func _on_cancel_pressed():
	# 如果要在取消時"還原"設定，需要比較複雜的邏輯
	# 目前簡單處理：直接關閉
	queue_free()

func show_window():
	self.show()
	
func _on_h_slider_value_changed(value: float) -> void:
	Global.volume_level = value

# 當勾選框切換時，直接更新 GlobalState
func _on_check_box_pressed() -> void:
	# 注意：CheckBox 的信號通常是 toggled(toggled_on)，但用 pressed 也可以配合 button_pressed 屬性
	var is_checked = ai_checkbox.button_pressed
	Global.is_ai_enabled = is_checked

func _on_close_requested() -> void:
	queue_free()
