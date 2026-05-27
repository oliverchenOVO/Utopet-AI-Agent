extends Control
@onready var chat_text: ChatText = $Character/ChatText
@onready var character = $Character
@onready var animated_sprite: AnimatedSprite2D = $Character/AnimatedSprite2D
@onready var right_click: PopupMenu = $right_click
@onready var character_area: Area2D = $Character/AnimatedSprite2D/Area2D
@onready var internet_window: Control = $internet
@onready var speak_window: Window = %speak_window

# DialogBox 保持你原本的寫法 (程式生成)
var dialog_box: Control 
var sentences: Array[String]
var is_loading = false

func _ready() -> void:
	# 視窗設定
	get_tree().root.set_transparent_background(true)
	get_window().borderless = true
	get_window().always_on_top = true
	get_window().transparent = true
	
	# --- DialogBox (維持原本的程式碼生成邏輯，不破壞舊系統) ---
	var dialog_scene = preload("res://Scene/dialog_box.tscn")
	dialog_box = dialog_scene.instantiate()
	add_child(dialog_box)
	dialog_box.visible = false 
	
	right_click.set_dialog_box(dialog_box)
	
	dialog_box.message_sent.connect(_on_dialog_box_message_sent)
	dialog_box.ai_response_received.connect(_on_ai_response_received)
	dialog_box.loading_started.connect(_on_loading_started)
	dialog_box.loading_finished.connect(_on_loading_finished)
	dialog_box.error_occurred.connect(_on_error_occurred)
	dialog_box.visibility_changed.connect(_update_mouse_passthrough_polygon)
	
	# --- ★ Internet 視窗設定 ---
	if internet_window.has_signal("ai_response_received"):
		internet_window.ai_response_received.connect(_on_ai_response_received)
	internet_window.visibility_changed.connect(_update_mouse_passthrough_polygon)
	# --- ★ 修正 3：接好右鍵選單與全新 speak_window 的串流訊號連線 ---
	right_click.id_pressed.connect(_on_right_click_id_pressed)
	if speak_window:
		if not speak_window.ai_stream_done.is_connected(_on_ai_stream_done):
			speak_window.ai_stream_done.connect(_on_ai_stream_done)
		# 為了滑鼠穿透安全，順便監聽它的可見度
		if not speak_window.emotion_triggered.is_connected(_on_speak_window_emotion_triggered):
			speak_window.emotion_triggered.connect(_on_speak_window_emotion_triggered)
			
		speak_window.visibility_changed.connect(_update_mouse_passthrough_polygon)
	
	# --- 其他設定 ---
	character_area.input_pickable = true
	character_area.input_event.connect(_on_area_2d_input_event)
	right_click.visibility_changed.connect(_update_mouse_passthrough_polygon)
	
	call_deferred("_update_mouse_passthrough_polygon")

# ★ 修正 4：新增處理右鍵選單所有點擊 ID 的總閘門
func _on_right_click_id_pressed(id: int) -> void:
	match id:
		10: # 當玩家在右鍵選單點選了 "talk"
			print("🔘 [主視窗] 收到右鍵點擊 talk，開啟全新對話視窗 speak_window！")
			if speak_window:
				speak_window.show_dialog() # 驅動彈出視窗

# ★ 修正 5：補上缺失的串流結束接收函數，完美對接你下方的 show_character_speech 函數！
func _on_ai_stream_done(full_response: String) -> void:
	print("🤖 [AI 串流結束] 完整回應：", full_response)
	show_character_speech("AI: " + full_response)


# ... (滑鼠穿透 _update_mouse_passthrough_polygon 等函數完全不用動，維持原樣) ...
func _update_mouse_passthrough_polygon():
	var has_ui_open = _check_visible_popups(self)
	if has_ui_open:
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array([]))
		return
	
	var clickable_polygons = []
	var sprite_texture = animated_sprite.sprite_frames.get_frame_texture(animated_sprite.animation, animated_sprite.frame)
	if sprite_texture:
		var texture_size = sprite_texture.get_size()
		var sprite_pos = animated_sprite.global_position
		var half_size = texture_size / 2 
		
		clickable_polygons.append([
			Vector2(sprite_pos.x - half_size.x, sprite_pos.y - half_size.y),
			Vector2(sprite_pos.x + half_size.x, sprite_pos.y - half_size.y),
			Vector2(sprite_pos.x + half_size.x, sprite_pos.y + half_size.y),
			Vector2(sprite_pos.x - half_size.x, sprite_pos.y + half_size.y)
		])
	
	var final_polygon = _merge_polygons(clickable_polygons)
	DisplayServer.window_set_mouse_passthrough(final_polygon)

func _check_visible_popups(node: Node) -> bool:
	if node == character: return false
	
	if node is Window or node is Popup or node is PopupPanel or node is AcceptDialog:
		if node.visible: return true
			
	if node is Control and node.visible:
		if node != self and node.name != "Character":
			return true
	
	for child in node.get_children():
		if _check_visible_popups(child):
			return true
	return false

func _merge_polygons(polygons: Array) -> PackedVector2Array:
	if polygons.is_empty(): return PackedVector2Array([])
	var min_x = INF; var min_y = INF; var max_x = -INF; var max_y = -INF
	for poly in polygons:
		for point in poly:
			min_x = min(min_x, point.x); min_y = min(min_y, point.y)
			max_x = max(max_x, point.x); max_y = max(max_y, point.y)
	return PackedVector2Array([Vector2(min_x, min_y), Vector2(max_x, min_y), Vector2(max_x, max_y), Vector2(min_x, max_y)])

func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int):
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			if right_click.visible: right_click.hide()
			else: right_click.popup_on_parent(Rect2i(mouse_event.global_position, Vector2i.ZERO))
			call_deferred("_update_mouse_passthrough_polygon")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"): get_tree().quit()

func _on_character_chat() -> void:
	pass

func _on_dialog_box_message_sent(message): show_character_speech("你: " + message)
func _on_ai_response_received(response: String): show_character_speech("AI: " + response)
func _on_loading_started(): show_character_speech("AI 正在思考中...")
func _on_loading_finished(): is_loading = false
func _on_error_occurred(error_message: String): show_character_speech("錯誤: " + error_message)

func show_character_speech(message: String):
	if chat_text:
		chat_text.text = message
		chat_text.play_chat()
func _on_speak_window_emotion_triggered(emotion_name: String) -> void:
	if character and character.has_method("play_emotion_animation"):
		character.play_emotion_animation(emotion_name)
