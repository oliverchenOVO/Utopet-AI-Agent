#work.gd
extends Panel
# 變數定義
var work_time: float = 0.0
var total_exp: int = 0
var exp_rate: float = 0.1 # 每秒增加多少經驗值

# 獲取節點引用 (根據你的場景命名調整)
@onready var time_label = $VBoxContainer/time
@onready var exp_label = $VBoxContainer/exp

func _process(delta):
	# 累加時間與計算經驗
	work_time += delta
	total_exp = int(work_time * exp_rate)
	
	# 更新 UI 顯示
	_update_ui()

func _update_ui():
	# 格式化時間為 HH:MM:SS
	var seconds = int(work_time) % 60
	var minutes = int(work_time / 60) % 60
	var hours = int(work_time / 3600)
	
	time_label.text = "  工作時間: %02d:%02d:%02d" % [hours, minutes, seconds]
	exp_label.text = "  獲得金錢: $ %d " % total_exp

func _on_work_pressed() -> void:
	pass # Replace with function body.
