# history_window.gd
extends Window

@onready var message_container = $Panel/ScrollContainer/VBoxContainer

func _ready():
	# 視窗屬性設定
	title = "對話歷史紀錄"
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	close_requested.connect(queue_free) # 按下 X 關閉視窗
	
	# ★ 載入時，把 GlobalState 裡的紀錄顯示出來
	load_history()

func load_history():
	# 先清空目前顯示的 (避免重複)
	for child in message_container.get_children():
		child.queue_free()
	
	# 讀取 GlobalState 的資料
	for log_data in Global.chat_history:
		add_message_bubble(log_data)
		
	# 等待一幀後自動捲動到底部
	await get_tree().process_frame
	_scroll_to_bottom()

func add_message_bubble(data: Dictionary):
	# 這裡我們用 RichTextLabel 來顯示，比較好做顏色區分
	var label = RichTextLabel.new()
	
	label.fit_content = true # 自動調整高度
	label.bbcode_enabled = true # 啟用 BBCode 做顏色
	label.custom_minimum_size = Vector2(300, 0) # 設定最小寬度
	
	var time_str = "[color=#888888][" + data["time"] + "][/color] "
	
	if data["role"] == "user":
		# 使用者說的話 (例如黃色)
		label.text = time_str + "[color=#FFFF00][你]:[/color] " + data["text"]
	else:
		# AI 說的話 (例如青色)
		label.text = time_str + "[color=#00FFFF][AI]:[/color] " + data["text"]
	
	# 加個底線分隔
	label.text += "\n[color=#333333]________________________[/color]"
	
	message_container.add_child(label)

func _scroll_to_bottom():
	# 取得 ScrollContainer 的捲軸並拉到底
	var scroll = $Panel/ScrollContainer
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
