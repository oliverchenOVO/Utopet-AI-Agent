extends PanelContainer

# 變數定義
var work_time: float = 0.0
var total_exp: int = 0
var exp_rate: float = 5.0 # 每秒增加多少經驗值

# 獲取節點引用 (根據你的場景命名調整)
@onready var time_label = $VBoxContainer/TimeLabel
@onready var exp_label = $VBoxContainer/ExpLabel
@onready var setting_button = $VBoxContainer/SettingButton

func _ready():
	# 連結按鈕點擊信號
	setting_button.pressed.connect(_on_setting_button_pressed)

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
	
	time_label.text = "工作時間: %02d:%02d:%02d" % [hours, minutes, seconds]
	exp_label.text = "累積經驗: %d XP" % total_exp

func _on_setting_button_pressed():
	# 切換到角色設定頁面
	# 注意：如果你的路徑不同，請修改此處
	get_tree().change_scene_to_file("res://character_setting.tscn")
