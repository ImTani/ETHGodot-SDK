extends Node2D

var console = JavaScriptBridge.get_interface("console")

func _ready() -> void:
	await get_tree().create_timer(5.0).timeout	
	Web3Manager.connect_wallet()
