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

# For batch testing - add more token addresses as needed
const TEST_TOKEN_ADDRESSES = [
	"0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
	"0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",  # Duplicate for testing
]

# ============================================================================
# Initialization
# ============================================================================

func _ready() -> void:
	# Check if Web3Manager autoload exists
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
	Web3Manager.transaction_failed.connect(_on_transaction_failed)
	Web3Manager.signature_successful.connect(_on_signature_successful)
	Web3Manager.contract_read_result.connect(_on_contract_read_result)
	Web3Manager.contract_read_batch_result.connect(_on_contract_read_batch_result)
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

func _on_connect_button_pressed() -> void:
	print("[Web3Tester] Connect button pressed")
	_clear_labels()
	if status_label:
		status_label.text = "Status: Connecting..."
	Web3Manager.connect_wallet()

func _on_disconnect_button_pressed() -> void:
	print("[Web3Tester] Disconnect button pressed")
	Web3Manager.disconnect_wallet()

func _on_reconnect_chain_button_pressed() -> void:
	print("[Web3Tester] Reconnect chain button pressed")
	_clear_labels()
	if response_label:
		response_label.text = "Reconnecting to current chain..."
	Web3Manager.reconnect_to_chain()

func _on_send_eth_button_pressed() -> void:
	print("[Web3Tester] Send ETH button pressed")
	_clear_labels()
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

func _on_sign_msg_button_pressed() -> void:
	print("[Web3Tester] Sign message button pressed")
	_clear_labels()
	var message = message_edit.text if message_edit else "Hello Godot Web3!"
	if message.is_empty():
		if error_label:
			error_label.text = "Error: Message cannot be empty."
		return
	
	if response_label:
		response_label.text = "Requesting signature for: '%s'" % message
	Web3Manager.sign_personal_message(message)

func _on_read_contract_button_pressed() -> void:
	print("[Web3Tester] Read contract button pressed")
	_clear_labels()
	if not Web3Manager.is_wallet_connected:
		if error_label:
			error_label.text = "Error: Wallet not connected."
		return
	
	if response_label:
		response_label.text = "Reading ERC20 balance for self..."
	Web3Manager.get_erc20_balance(TEST_ERC20_ADDRESS, Web3Manager.account_address, "my_balance_call")

func _on_read_batch_button_pressed() -> void:
	print("[Web3Tester] Read batch button pressed")
	_clear_labels()
	if not Web3Manager.is_wallet_connected:
		if error_label:
			error_label.text = "Error: Wallet not connected."
		return
	
	# Create batch of balance reads for multiple tokens
	var batch_params = []
	var balance_abi = '[{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"stateMutability":"view","type":"function"}]'
	
	for token_address in TEST_TOKEN_ADDRESSES:
		batch_params.append({
			"address": token_address,
			"abi": balance_abi,
			"function_name": "balanceOf",
			"args": [Web3Manager.account_address],
			"call_id": "batch_balance_" + token_address
		})
	
	if response_label:
		response_label.text = "Reading %d token balances in batch..." % batch_params.size()
	Web3Manager.call_contract_batch(batch_params)

func _on_write_contract_button_pressed() -> void:
	print("[Web3Tester] Write contract button pressed")
	_clear_labels()
	if not Web3Manager.is_wallet_connected:
		if error_label:
			error_label.text = "Error: Wallet not connected."
		return
	
	# Approve another address (e.g., a DEX) to spend your tokens
	var spender_address = TEST_RECIPIENT_ADDRESS
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
		response_label.text = "Network switched! Call reconnect_to_chain() to update clients."

func _on_transaction_response(tx_hash: String) -> void:
	print("[Web3Tester] Transaction response signal received: ", tx_hash)
	if response_label:
		response_label.text = "Tx Response Hash:\n" + tx_hash + "\nWaiting for receipt..."

func _on_transaction_receipt(receipt: JavaScriptObject) -> void:
	print("[Web3Tester] Transaction receipt signal received")
	
	# Access JavaScriptObject properties directly
	var tx_hash = receipt.transactionHash
	var block_number = receipt.blockNumber
	var gas_used = receipt.gasUsed
	var status = receipt.status
	
	print("[Web3Tester] Hash: ", tx_hash)
	print("[Web3Tester] Block: ", block_number)
	print("[Web3Tester] Gas: ", gas_used)
	print("[Web3Tester] Status: ", status)
	
	var status_text = "Success" if status == "success" else "Failed"
	
	if response_label:
		response_label.text = "Tx Receipt!\nHash: %s\nBlock: %s\nGas: %s\nStatus: %s" % [
			Web3Manager.format_address_short(tx_hash),
			block_number,
			gas_used,
			status_text
		]

func _on_transaction_failed(tx_hash: String, error_message: String) -> void:
	print("[Web3Tester] Transaction failed signal received: ", tx_hash, " - ", error_message)
	if error_label:
		error_label.text = "Transaction Failed!\nHash: %s\nError: %s" % [
			Web3Manager.format_address_short(tx_hash),
			error_message
		]

func _on_signature_successful(signature: String, original_data: Variant) -> void:
	print("[Web3Tester] Signature successful signal received")
	if response_label:
		response_label.text = "Signature Successful:\n" + signature.substr(0, 20) + "..."

func _on_contract_read_result(result: Variant, call_id: String) -> void:
	print("[Web3Tester] Contract read result signal received: ", call_id, " = ", result)
	
	# Handle specific read calls
	if call_id == "my_balance_call":
		var balance_float = Web3Manager.wei_to_float(str(result))
		if response_label:
			response_label.text = "Contract Read Result (balanceOf):\n%s tokens" % str(balance_float)
	else:
		if response_label:
			response_label.text = "Contract Read (%s):\n%s" % [call_id, str(result)]

func _on_contract_read_batch_result(results: Array, batch_id: String) -> void:
	print("[Web3Tester] Contract read batch result signal received: ", results.size(), " results")
	
	var result_text = "Batch Read Complete (%d results):\n" % results.size()
	
	for i in range(results.size()):
		var balance_float = Web3Manager.wei_to_float(str(results[i]))
		result_text += "Token %d: %s tokens\n" % [i + 1, balance_float]
	
	if response_label:
		response_label.text = result_text

func _on_web3_error(error_code: int, error_message: String, operation_id: String) -> void:
	print("[Web3Tester] Web3 error signal received: ", error_code, " - ", error_message)
	if error_label:
		error_label.text = "Web3 Error!\nCode: %d\nOp: %s\nMessage: %s" % [error_code, operation_id, error_message]
	if status_label:
		status_label.text = "Status: Error occurred"

# ============================================================================
# Helper Functions
# ============================================================================

func _clear_labels() -> void:
	if response_label:
		response_label.text = ""
	if error_label:
		error_label.text = ""
