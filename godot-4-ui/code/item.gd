# item.gd (附加到 item.tscn 的根節點)
extends PanelContainer

@onready var buy: Button = $VBoxContainer/HBoxContainer/buy
@onready var price_label: Label = $VBoxContainer/HBoxContainer/price/price_label
@onready var count_label: Label = $VBoxContainer/HBoxContainer3/count_label
@onready var item_name: Label = $VBoxContainer/Item_name
@onready var item_icon: TextureRect = $VBoxContainer/HBoxContainer2/item_icon

# 使用成員變數儲存資料（更可靠）
var _item_price: int = 0
var _item_name: String = ""
var _item_id: int = 0
var _item_icon_path: String = ""  # 儲存圖標路徑

# ----------------------------------------------------------------------

# 公共函數：用於設定 Item 的內容 (由 market.gd 呼叫)
func set_item_data(p_name: String, texture: Texture2D, count: int, price: int, item_id: int, icon_path: String = ""):
	print("\n=== 設定物品資料: %s ===" % p_name)
	
	_item_price = price
	_item_name = p_name       
	_item_id = item_id
	_item_icon_path = icon_path  

	if price_label:
		price_label.text = str(price)
	
	if count_label:
		count_label.text = str(count)
	
	if item_name:
		item_name.text = p_name   
	
	if item_icon and texture:
		item_icon.texture = texture

func _ready():
	pass

func _on_buy_pressed() -> void:
	# 傳遞圖標路徑
	var success = Global.try_purchase(_item_price, _item_name, _item_icon_path)
	
	if success:
		print("✓ 成功購買 %s (ID: %d)" % [_item_name, _item_id])
	else:
		print("✗ 購買失敗：金錢不足")
