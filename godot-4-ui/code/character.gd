extends Node2D
class_name Character

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_timer: Timer = $Timer

signal chat

func _ready() -> void:
	animated_sprite_2d.play("Relax")
	
func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# 左鍵拖移 (移動中)
	if event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MASK_LEFT:
		get_tree().root.position += Vector2i(event.relative)
		
		# --- 新增：如果當前不是 Move 動畫就切換 ---
		if animated_sprite_2d.animation != "Move":
			animated_sprite_2d.play("Move")
	
	# 滑鼠按鍵事件
	if event is InputEventMouseButton:
		if event.pressed: # 按下時
			if event.button_index == MOUSE_BUTTON_LEFT:
				play_interact_animation()
				chat.emit()
				animation_timer.start()
		else: # --- 新增：放開按鍵時 (停止移動) ---
			if event.button_index == MOUSE_BUTTON_LEFT:
				play_relax_animation()

# Timer 的 timeout 信号回调
func _on_timer_timeout():
	print("Character: 计时器结束，切换到 relax")
	play_relax_animation()

func play_interact_animation():
	print("Character: 播放 interact 動畫")
	animated_sprite_2d.stop()
	animated_sprite_2d.play("Interact")

func play_relax_animation():
	# --- 新增：檢查防止重複觸發 ---
	if animated_sprite_2d.animation == "Relax": return
	
	print("Character: 播放 relax 動畫")
	animated_sprite_2d.stop()
	animated_sprite_2d.play("Relax")

func get_current_animation() -> String:
	return animated_sprite_2d.animation

func play_emotion_animation(emotion_name: String) -> void:
	print("Character: 收到情緒要求 -> ", emotion_name)
	
	# 停止當前計時器或動畫，避免衝突
	animation_timer.stop() 
	animated_sprite_2d.stop()
	
	match emotion_name:
		"快樂":animated_sprite_2d.play("Happy")   
		"難過":animated_sprite_2d.play("Sad")
		"生氣":animated_sprite_2d.play("Angry")
		"害怕":animated_sprite_2d.play("Scared")
	animation_timer.start()

# 動畫完成時的處理（需要連接信號）
func _on_animated_sprite_2d_animation_finished():
	print("動畫播放完成：", animated_sprite_2d.animation)
	var reset_animations = ["Interact", "Happy", "Sad", "Angry", "Scared"]
	if animated_sprite_2d.animation in reset_animations:
		play_relax_animation()
