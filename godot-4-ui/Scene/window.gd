extends Window

@onready var character_info = $Panel/character_info
@onready var backpack_panel = $Panel/backpack
@onready var market_panel = $Panel/market
@onready var work_display = $Panel/work_display
@onready var time_label = $Panel/work_display/TimeLabel

@onready var work_manager = get_tree().root.get_node_or_null("MainWindow/WorkManager")

func _ready() -> void:
	visible = false
	get_window().always_on_top = true
	_show_tab(character_info)
	
	if work_manager:
		# 檢查信號是否連接成功
		if not work_manager.work_time_updated.is_connected(_on_work_time_updated):
			work_manager.work_time_updated.connect(_on_work_time_updated)
		print("成功連接到 WorkManager")
	else:
		print("警告：找不到 MainWindow/WorkManager 節點！")

func _on_work_time_updated(formatted_time: String) -> void:
	# 強制更新文字
	if time_label:
		time_label.text = "努力工作中...\n" + formatted_time
	else:
		print("找不到 TimeLabel 節點")

func _on_work_pressed() -> void:
	if work_manager:
		var working = work_manager.toggle_work()
		if working:
			_show_tab(work_display)
		else:
			_show_tab(character_info)

func _show_tab(target_panel: Panel) -> void:
	# 確保切換時，目標面板是可見的，其他是隱藏的
	character_info.visible = (target_panel == character_info)
	backpack_panel.visible = (target_panel == backpack_panel)
	market_panel.visible = (target_panel == market_panel)
	work_display.visible = (target_panel == work_display)

# 其餘按鈕...
func _on_home_pressed(): _show_tab(character_info)
func _on_backpack_pressed(): _show_tab(backpack_panel)
func _on_market_pressed(): _show_tab(market_panel)

func _on_close_requested():
	hide()
