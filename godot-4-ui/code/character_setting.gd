# character_setting.gd
extends Window

@onready var character_info: Panel = $Panel/character_info
@onready var backpack: Panel = $Panel/backpack
@onready var market: Panel = $Panel/market
@onready var work: Panel = $Panel/work
@onready var setting: Panel = $Panel/setting
@onready var schedule: Window = %speak_window
@onready var all_panels = [character_info, backpack, market, work, setting]
@export var schedule_offset: Vector2i = Vector2i(83, 0)

func _ready() -> void:
	visible = false
	
	if schedule:
		schedule.visible = false
	# 初始化：顯示首頁
	_switch_to_panel(character_info)
	
# 核心切換邏輯
func _switch_to_panel(target_panel: Control):
	for p in all_panels:
		p.visible = (p == target_panel)

	if schedule:
		schedule.visible = false

# --- 按鈕事件 ---

func _on_home_pressed() -> void:
	_switch_to_panel(character_info)

func _on_backpack_pressed() -> void:
	_switch_to_panel(backpack)

func _on_market_pressed() -> void:
	_switch_to_panel(market)

func _on_work_pressed() -> void:
	_switch_to_panel(work)

func _on_settings_pressed() -> void:
	_switch_to_panel(setting)

func _on_schedule_pressed() -> void:
	for p in all_panels:
		p.visible = (p == character_info)
	if schedule:
		schedule.visible = true
		if schedule.has_method("show_window"):
			schedule.show_window()
		else:
			schedule.popup_centered() 
		schedule.position = self.position + schedule_offset
		
		schedule.grab_focus()
		schedule.always_on_top = true
		if schedule.has_method("fetch_and_show_schedule"):
			schedule.fetch_and_show_schedule()
			print("🎯 [CharacterSetting] 已成功點擊日程，通知 speak_window 發送請求")

func _on_close_requested() -> void:
	hide()
