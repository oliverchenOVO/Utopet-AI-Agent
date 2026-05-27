extends Control

@onready var input_field: LineEdit = $Panel/VBoxContainer/HBoxContainer/input_field
@onready var send_button: Button = $Panel/VBoxContainer/HBoxContainer/SendButton

var http_request: HTTPRequest

# ★ 1. 定義跟 dialog_box 一模一樣的信號
signal ai_response_received(response: String)

const API_URL = "http://127.0.0.1:8000/summarize/article"

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.timeout = 30.0
	http_request.request_completed.connect(_on_request_completed)
	
	send_button.pressed.connect(_on_send_pressed)

func _on_send_pressed():
	var text_content = input_field.text.strip_edges()
	if text_content == "":
		return
		
	# 發送請求給 Python
	var data = { "title": "分析文章", "text": text_content }
	var json_str = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]
	
	http_request.request(API_URL, headers, HTTPClient.METHOD_POST, json_str)
	
	input_field.text = ""
	visible = false 

func _on_request_completed(_result, response_code, _headers, body):
	if response_code == 200:
		var json = JSON.new()
		var parse_err = json.parse(body.get_string_from_utf8())
		
		if parse_err == OK:
			var response = json.data
			if response["success"]:
				# 整理文字
				var final_output = "\n【網頁分析報告】\n" + response["summary"]
				if response["points"].size() > 0:
					final_output += "\n\n關鍵重點：\n"
					for p in response["points"]:
						final_output += "• " + str(p) + "\n"
				final_output += "\n----------------------\n"
				
				# ★ 2. 發出信號！ (這就是 dialog_box 的作法)
				# 我們不自己去填字，而是大喊「我有結果了」，讓外面接線的人去處理
				emit_signal("ai_response_received", final_output)
				
			else:
				print("Python API 錯誤: ", response["error"])
	else:
		print("連線失敗: ", response_code)
