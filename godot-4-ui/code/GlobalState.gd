# GlobalState.gd
extends Node

# 金錢邏輯
var player_money: int = 45 : 
	set(value):
		if player_money != value:
			player_money = value
			money_changed.emit(player_money)
var hunger: float = 100.0 
var max_hunger: int = 100
var favor: float = 0.0

signal money_changed(new_money: int)
signal item_added(item_name: String, icon_path: String, count: int)

func try_purchase(price: int, item_name: String = "", item_icon: String = "") -> bool:
	if player_money >= price:
		self.player_money = player_money - price
		print("購買成功！花了 %d 購買 %s，剩餘金錢: %d" % [price, item_name, player_money])
		item_added.emit(item_name, item_icon, 1)
		return true
	else:
		print("金錢不足，無法購買 %s (需要 %d, 只有 %d)" % [item_name, price, player_money])
		return false

# 1. AI 開關變數
signal ai_state_changed(is_enabled: bool)
var is_ai_enabled: bool = true: # 預設開啟
	set(value):
		is_ai_enabled = value
		ai_state_changed.emit(is_ai_enabled)
		print("GlobalState: AI 功能已", "開啟" if is_ai_enabled else "關閉")

# 2. 音量變數 (假設 slider 是 0~100)
signal volume_changed(new_volume: float)
var volume_level: float = 50.0: # 預設 50%
	set(value):
		volume_level = value
		volume_changed.emit(volume_level)
		# 這裡可以直接控制全域音量 (如果你的聲音是透過 AudioServer)
		# AudioServer.set_bus_volume_db(0, linear_to_db(value / 100.0))
		print("GlobalState: 音量調整為", value)

# 歷史紀錄資料庫
# 格式範例：[{"role": "user", "text": "你好"}, {"role": "ai", "text": "你好！有什麼我可以幫你的？"}]
var chat_history: Array[Dictionary] = []
# 增加紀錄的輔助函數
func add_history(role: String, text: String):
	chat_history.append({
		"role": role,
		"text": text,
		"time": Time.get_time_string_from_system() # 順便紀錄時間 (HH:MM:SS)
	})
	print("已紀錄對話: ", role, " - ", text)
