extends Control

@export var status_label: Label
@export var address_label: Label
@export var chain_id_label: Label
@export var response_label: Label
@export var error_label: Label
@export var recipient_edit: LineEdit
@export var message_edit: LineEdit

# ============================================================================
# Test Configuration - !! UPDATE THESE PLACEHOLDERS !!
# ============================================================================

# Replace with a valid recipient address on your test network (e.g., Sepolia)
const TEST_RECIPIENT_ADDRESS = "0xDE41F7a15f81A7720957390dc5fe3C0C72B0D6d7"

# Replace with a valid ERC20 token contract address on your test network
const TEST_ERC20_ADDRESS = "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"

# ============================================================================
# Initialization
# ============================================================================

func _ready() -> void:
	# FIXED: Check if Web3Manager autoload exists using has_node
	if not has_node("/root/Web3Manager"):
		push_error("Web3Manager autoload not found. Please add Web3Manager.gd to Project > Project Settings > Autoload.")
		if status_label:
			status_label.text = "Error: Web3Manager not found."
		return

	# Connect to all signals from the Web3Manager
	Web3Manager.wallet_connected.connect(_on_wallet_connected)
	Web3Manager.wallet_disconnected.connect(_on_wallet_disconnected)
	Web3Manager.account_changed.connect(_on_account_changed)
	Web3Manager.chain_changed.connect(_on_chain_changed)
	Web3Manager.transaction_response.connect(_on_transaction_response)
	Web3Manager.transaction_receipt.connect(_on_transaction_receipt)
	Web3Manager.signature_successful.connect(_on_signature_successful)
	Web3Manager.contract_read_result.connect(_on_contract_read_result)
	Web3Manager.web3_error.connect(_on_web3_error)

	# Initial UI state
	if status_label:
		status_label.text = "Status: Not Connected"
	if address_label:
		address_label.text = "Address: N/A"
	if chain_id_label:
		chain_id_label.text = "Chain ID: N/A"
	if response_label:
		response_label.text = ""
	if error_label:
		error_label.text = ""
	if recipient_edit:
		recipient_edit.text = TEST_RECIPIENT_ADDRESS
	if message_edit:
		message_edit.text = "Hello Godot Web3!"
	
	print("[Web3Tester] Initialized and ready")

# ============================================================================
# UI Button Handlers
# ============================================================================

func _on_ConnectButton_pressed() -> void:
	print("[Web3Tester] Connect button pressed")
	clear_labels()
	if status_label:
		status_label.text = "Status: Connecting..."
	Web3Manager.connect_wallet()

func _on_DisconnectButton_pressed() -> void:
	print("[Web3Tester] Disconnect button pressed")
	Web3Manager.disconnect_wallet()

func _on_SendEthButton_pressed() -> void:
	print("[Web3Tester] Send ETH button pressed")
	clear_labels()
	var recipient = recipient_edit.text if recipient_edit else TEST_RECIPIENT_ADDRESS
	if not Web3Manager.is_valid_address(recipient):
		if error_label:
			error_label.text = "Error: Invalid recipient address format."
		return
	
	# Send 0.001 of the native token (e.g., ETH)
	var amount_wei = Web3Manager.float_to_wei(0.001)
	if response_label:
		response_label.text = "Sending %s wei to %s..." % [amount_wei, Web3Manager.format_address_short(recipient)]
	Web3Manager.send_native_token(recipient, amount_wei)

func _on_SignMsgButton_pressed() -> void:
	print("[Web3Tester] Sign message button pressed")
	clear_labels()
	var message = message_edit.text if message_edit else "Hello Godot Web3!"
	if message.is_empty():
		if error_label:
			error_label.text = "Error: Message cannot be empty."
		return
	
	if response_label:
		response_label.text = "Requesting signature for: '%s'" % message
	Web3Manager.sign_personal_message(message)

func _on_ReadContractButton_pressed() -> void:
	print("[Web3Tester] Read contract button pressed")
	clear_labels()
	if not Web3Manager.is_wallet_connected:
		if error_label:
			error_label.text = "Error: Wallet not connected."
		return
	
	if response_label:
		response_label.text = "Reading ERC20 balance for self..."
	Web3Manager.get_erc20_balance(TEST_ERC20_ADDRESS, Web3Manager.account_address, "my_balance_call")

func _on_WriteContractButton_pressed() -> void:
	print("[Web3Tester] Write contract button pressed")
	clear_labels()
	if not Web3Manager.is_wallet_connected:
		if error_label:
			error_label.text = "Error: Wallet not connected."
		return
	
	# This is a common test: Approving another address (e.g., a DEX) to spend your tokens.
	# We'll approve a test address to spend 1 token (with 18 decimals).
	var spender_address = TEST_RECIPIENT_ADDRESS # Re-using for simplicity
	var amount_wei = Web3Manager.float_to_wei(1.0)
	
	if response_label:
		response_label.text = "Approving %s to spend 1 token..." % Web3Manager.format_address_short(spender_address)
	Web3Manager.approve_erc20(TEST_ERC20_ADDRESS, spender_address, amount_wei)

# ============================================================================
# Web3Manager Signal Handlers
# ============================================================================

func _on_wallet_connected(address: String, chain_id: int) -> void:
	print("[Web3Tester] Wallet connected signal received: ", address, " chain: ", chain_id)
	if status_label:
		status_label.text = "Status: Connected"
	if address_label:
		address_label.text = "Address: " + address
	if chain_id_label:
		chain_id_label.text = "Chain ID: " + str(chain_id)

func _on_wallet_disconnected() -> void:
	print("[Web3Tester] Wallet disconnected signal received")
	if status_label:
		status_label.text = "Status: Disconnected"
	if address_label:
		address_label.text = "Address: N/A"
	if chain_id_label:
		chain_id_label.text = "Chain ID: N/A"

func _on_account_changed(new_address: String) -> void:
	print("[Web3Tester] Account changed signal received: ", new_address)
	if address_label:
		address_label.text = "Address (changed): " + new_address
	if response_label:
		response_label.text = "Account switched in wallet!"

func _on_chain_changed(new_chain_id: int) -> void:
	print("[Web3Tester] Chain changed signal received: ", new_chain_id)
	if chain_id_label:
		chain_id_label.text = "Chain ID (changed): " + str(new_chain_id)
	if response_label:
		response_label.text = "Network switched in wallet!"

func _on_transaction_response(hash: String) -> void:
	print("[Web3Tester] Transaction response signal received: ", hash)
	if response_label:
		response_label.text = "Tx Response Hash:\n" + hash + "\nWaiting for receipt..."

func _on_transaction_receipt(receipt: Dictionary) -> void:
	print("[Web3Tester] Transaction receipt signal received: ", receipt)
	var tx_hash = receipt.get("transactionHash", "N/A")
	var status = "Success" if receipt.get("status", "failure") == "success" else "Failed"
	if response_label:
		response_label.text = "Tx Receipt! Hash: %s\nStatus: %s" % [Web3Manager.format_address_short(tx_hash), status]

func _on_signature_successful(signature: String, original_data: Variant) -> void:
	print("[Web3Tester] Signature successful signal received")
	if response_label:
		response_label.text = "Signature Successful:\n" + signature

func _on_contract_read_result(result: Variant, call_id: String) -> void:
	print("[Web3Tester] Contract read result signal received: ", call_id, " = ", result)
	# Handle our specific read call
	if call_id == "my_balance_call":
		var balance_float = Web3Manager.wei_to_float(str(result))
		if response_label:
			response_label.text = "Contract Read Result (balanceOf):\n%s tokens" % str(balance_float)
	else:
		if response_label:
			response_label.text = "Contract Read (%s):\n%s" % [call_id, str(result)]

func _on_web3_error(error_code: int, error_message: String, operation_id: String) -> void:
	print("[Web3Tester] Web3 error signal received: ", error_code, " - ", error_message)
	if error_label:
		error_label.text = "Web3 Error!\nCode: %d\nOp: %s\nMessage: %s" % [error_code, operation_id, error_message]
	if status_label:
		status_label.text = "Status: Error occurred"

# ============================================================================
# Helper Functions
# ============================================================================

func clear_labels() -> void:
	if response_label:
		response_label.text = ""
	if error_label:
		error_label.text = ""
