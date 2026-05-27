extends Control

@onready var input_website: LineEdit = $Panel/VBoxContainer/HBoxContainer/input_website
@onready var send: Button = $Panel/VBoxContainer/HBoxContainer/send

signal message_sent(message: String)
signal ai_response_received(response: String)
signal loading_started()
signal loading_finished()
signal error_occurred(error_message: String)

var http_request: HTTPRequest
const SERVER_URL = "http://127.0.0.1:8000"

func _ready() -> void:
	visible = false
	http_request = HTTPRequest.new()

func send_message():
	pass
		
func _on_send_pressed() -> void:
	pass # Replace with function body.


func _on_input_website_text_submitted(new_text: String) -> void:
	pass # Replace with function body.
