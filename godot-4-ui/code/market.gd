# market.gd
extends Panel

const ITEM_SCENE = preload("res://Scene/item.tscn")
@onready var prodcut: GridContainer = $market/VBoxContainer/VScrollBar/prodcut

var shop_data = [
	{"id": 1, "name": "麵包", "price": 10, "texture": preload("res://Assets/PNG/items/bread.png"), "icon_path": "res://Scene/bread.png", "initial_bag_count": 3},
	{"id": 2, "name": "雞蛋吐司", "price": 15, "texture": preload("res://Assets/PNG/items/bread.png"), "icon_path": "res://Scene/Egg_toast-.png", "initial_bag_count": 0},
	{"id": 3, "name": "熱狗麵包", "price": 25, "texture": preload("res://Assets/PNG/items/bread.png"), "icon_path": "res://Scene/hot_dog_bread.png", "initial_bag_count": 0},
	{"id": 4, "name": "紅豆麵包", "price": 12, "texture": preload("res://Assets/PNG/items/bread.png"), "icon_path": "res://Scene/Red_bean_bread.png", "initial_bag_count": 0},
	{"id": 5, "name": "巧克力麵包", "price": 30, "texture": preload("res://Assets/PNG/items/bread.png"), "icon_path": "res://Assets/PNG/items/Bread Vector.jpg", "initial_bag_count": 0},
	{"id": 6, "name": "菠蘿麵包", "price": 18, "texture": preload("res://Assets/PNG/items/bread.png"), "icon_path": "res://Assets/PNG/items/Bread Vector.jpg", "initial_bag_count": 0},
]

func _ready() -> void:
	generate_market_items()
	
func generate_market_items():
	for item_data in shop_data:
		var new_item = ITEM_SCENE.instantiate()
		
		# 1. 【關鍵修改】先將物品加入場景，讓 item.gd 的 @onready 跑起來
		prodcut.add_child(new_item)
		
		# --- 資料準備 ---
		var item_id = item_data.id as int
		var item_name = item_data.name as String
		var item_price = item_data.price as int
		var icon_path = item_data.get("icon_path", "") as String
		var player_inventory_count = 0 
		var item_texture: Texture2D
		# 檢查路徑是否存在且有效
		if icon_path != "" and ResourceLoader.exists(icon_path):
			item_texture = load(icon_path)
		else:
			print("提示: 找不到圖片 ", icon_path, "，使用預設圖片。")
			item_texture = item_data.texture as Texture2D
		
		# 2. 現在 item_icon 已經準備好了，可以安全地設定資料
		new_item.set_item_data(item_name, item_texture, player_inventory_count, item_price, item_id, icon_path)
		
		new_item.set_item_data(item_name, item_texture, player_inventory_count, item_price, item_id, icon_path)


func _on_market_pressed() -> void:
	pass # Replace with function body.
