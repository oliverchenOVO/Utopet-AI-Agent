extends Panel
# 不再使用固定路徑，改用動態搜尋
var hunger_bar: ProgressBar
var favor_bar: ProgressBar

func _ready():
	# 自動搜尋子節點，不論路徑多深
	hunger_bar = find_child("HungerBar", true, false) as ProgressBar
	favor_bar = find_child("FavorBar", true, false) as ProgressBar
	update_ui()

func _process(delta):
	# 飽食度隨時間減少
	if Global.hunger > 0:
		Global.hunger -= 0.2 * delta
	else:
		Global.hunger = 0
	
	update_ui()

func update_ui():
	# 只有在抓到節點的情況下才更新數值
	if is_instance_valid(hunger_bar):
		hunger_bar.value = Global.hunger
	
	if is_instance_valid(favor_bar):
		favor_bar.value = Global.favor
