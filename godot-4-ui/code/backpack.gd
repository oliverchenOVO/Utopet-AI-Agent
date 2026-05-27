# backpack.gd
extends Panel

var inventory_data = {}
var max_slots = 12
@onready var grid_container: GridContainer = $backpack/VBoxContainer/VBoxContainer/GridContainer

func _ready() -> void:
	setup_inventory_grid()
	# 連接 Global 的物品添加信號
	Global.item_added.connect(_on_item_added)
	
	# 測試：添加一個物品看看
	add_item("麵包", "res://Assets/PNG/items/bread.png", 3)

# 當購買物品時被呼叫
func _on_item_added(item_name: String, icon_path: String, count: int):
	print("背包收到物品: %s x%d" % [item_name, count])
	add_item(item_name, icon_path, count)

func setup_inventory_grid():
	grid_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	for i in range(max_slots):
		var slot = create_inventory_slot(i)
		grid_container.add_child(slot)

func create_inventory_slot(index: int) -> Panel:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(40, 40)
	slot.name = "Slot" + str(index)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.3)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.5, 0.5)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	slot.add_theme_stylebox_override("panel", style)
	
	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(30, 30)
	icon.position = Vector2(5, 5)
	icon.visible = false
	slot.add_child(icon)
	
	var label = Label.new()
	label.name = "Count"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.position = Vector2(30, 20)
	label.size = Vector2(10, 10)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.visible = false
	slot.add_child(label)
	
	return slot

func add_item(item_name: String, icon_path: String, count: int = 1):
	# 先檢查是否已經有相同物品，如果有就增加數量
	for i in inventory_data:
		if inventory_data[i]["name"] == item_name:
			inventory_data[i]["count"] += count
			update_slot_display(i)
			print("物品堆疊: %s 現在有 %d 個" % [item_name, inventory_data[i]["count"]])
			return
	
	# 如果沒有相同物品，找空格子
	for i in range(max_slots):
		if i not in inventory_data:
			inventory_data[i] = {
				"name": item_name,
				"icon": icon_path,
				"count": count
			}
			update_slot_display(i)
			print("新物品放入格子 %d: %s x%d" % [i, item_name, count])
			return
	
	print("背包已滿！無法添加 %s" % item_name)

func update_slot_display(slot_index: int):
	if slot_index >= grid_container.get_child_count():
		return
		
	var slot = grid_container.get_child(slot_index)
	if slot_index in inventory_data:
		var data = inventory_data[slot_index]
		var icon = slot.get_node("Icon")
		var label = slot.get_node("Count")
		
		if ResourceLoader.exists(data["icon"]):
			icon.texture = load(data["icon"])
			icon.visible = true
		
		label.text = str(data["count"])
		label.visible = true


func _on_use_pressed() -> void:
	pass # Replace with function body.
