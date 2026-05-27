extends Panel

@onready var money_label: Label = $Panel/money_label


# 引用顯示金錢( Label ) 
const ITEM_SCENE = preload("res://Scene/item.tscn")
func _ready():
	# 1. 初始化顯示：從 Global 腳本讀取當前金錢值
	money_label.text = str(Global.player_money)
	# 2. 連接信號：當 Global 腳本的金錢變動時，呼叫 _on_money_changed
	# 語法：Global.信號名稱.connect(函數名稱)
	Global.money_changed.connect(_on_money_changed)
# 當 Global 腳本發出信號時，這個函數會被自動呼叫
func _on_money_changed(new_money: int):
	 # 更新 Label 的文字
	money_label.text = str(new_money)
