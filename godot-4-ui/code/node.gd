extends Node

# --- 基礎數值 ---
var current_exp: float = 0.0
var level: int = 1
var is_working: bool = false

# --- 配置 (可調整) ---
const EXP_PER_SECOND = 2.0       # 每秒獲得的基礎經驗
const LEVEL_UP_BASE = 100.0      # 1級升2級需要的經驗
const LEVEL_UP_FACTOR = 1.2      # 每級經驗需求增幅 (1.2倍)

# 引用 Timer
@onready var work_timer = $WorkTimer

func _ready():
	# 連接 Timer 信號
	work_timer.timeout.connect(_on_work_tick)
	print("工作系統已就緒，目前等級: ", level)

# --- 外部呼叫接口 ---

func start_working():
	is_working = true
	print("桌寵開始工作...")

func stop_working():
	is_working = false
	print("桌寵停止工作。")

# --- 核心邏輯 ---

func _on_work_tick():
	if not is_working:
		return
	
	# 1. 增加經驗
	var gained_exp = EXP_PER_SECOND
	current_exp += gained_exp
	
	# 2. 檢查升級
	_check_level_up()
	
	# 你可以在這裡發送信號給 UI 更新進度條
	# emit_signal("work_progress_updated", current_exp, get_required_exp())

func _check_level_up():
	var required_exp = get_required_exp()
	
	while current_exp >= required_exp:
		current_exp -= required_exp
		level += 1
		_on_level_up()
		# 重新計算下一級所需經驗
		required_exp = get_required_exp()

func get_required_exp() -> float:
	# 計算公式: 基礎值 * (增幅係數 ^ (等級-1))
	return LEVEL_UP_BASE * pow(LEVEL_UP_FACTOR, level - 1)

func _on_level_up():
	print("恭喜升級！目前等級: ", level)
	# 這裡可以加入升級特效或音效
