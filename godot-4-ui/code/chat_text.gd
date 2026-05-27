extends Label
class_name ChatText

@onready var timer: Timer = $Timer
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func play_chat() -> void:
	pass

func _on_timer_timeout() -> void:
	print("ChatText: 計時器結束，隱藏文字")
