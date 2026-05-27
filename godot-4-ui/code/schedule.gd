extends Panel

# 如果你需要動態生成才用這個，但建議直接引用場景中的實例
var speak_window_scene = preload("res://Scene/speak_window.tscn")
var speak_window = null

func _on_index_pressed(id: int):
	match id:
		11: 
			_on_speaknow_window()

# --- 按鈕功能 ---
func _on_speaknow_window():
	# 隱藏右鍵選單面板
	visible = false 
	
	# 獲取 MainWindow 節點
	var main_window = get_tree().root.get_node("MainWindow")
	
	# 獲取 character_setting 節點 (這是在 MainWindow 下的子節點)
	var char_setting = main_window.get_node_or_null("character_setting")
	
	if char_setting:
		# 1. 顯示角色設定大視窗
		char_setting.show() 
		
		# 2. 呼叫我們寫在 character_setting.gd 裡的函數
		# 該函數會自動執行：切換到 character_info 面板 + 彈出 speak_window
		if char_setting.has_method("_on_schedule_pressed"):
			char_setting._on_schedule_pressed()
	else:
		# 如果找不到 character_setting，才走原本的動態生成邏輯（保險用）
		_fallback_spawn_logic(main_window)

# 保險邏輯：如果 character_setting 沒在場景裡，就自己生一個視窗
func _fallback_spawn_logic(main_window):
	if not speak_window:
		speak_window = speak_window_scene.instantiate()
		main_window.add_child(speak_window)
		# 這裡連接你的訊號... (保持你原本的連線程式碼)
	
	speak_window.show_window()
