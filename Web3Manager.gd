# Web3Manager.gd
# Autoload singleton for Web3 blockchain integration.
# FIXED: Proper Dictionary to JavaScript Object conversion
# Add this script in Project Settings > Autoload with the name "Web3Manager".

extends Node

# ============================================================================
# SIGNALS - Asynchronous communication bus for Web3 events
# ============================================================================

## Emitted when wallet connection is successful
signal wallet_connected(address: String, chain_id: int)

## Emitted when wallet is disconnected
signal wallet_disconnected()

## Emitted when user switches account in wallet
signal account_changed(new_address: String)

## Emitted when user switches blockchain network
signal chain_changed(new_chain_id: int)

## Emitted immediately after transaction submission
signal transaction_response(hash: String)

## Emitted when transaction is mined and confirmed
signal transaction_receipt(receipt: Dictionary)

## Emitted after successful message or typed data signing
signal signature_successful(signature: String, original_data: Variant)

## Emitted with result of read-only contract call
signal contract_read_result(result: Variant, call_id: String)

## Emitted on any Web3 operation failure
signal web3_error(error_code: int, error_message: String, operation_id: String)

# ============================================================================
# STATE PROPERTIES
# ============================================================================

## Current connection status
var is_wallet_connected: bool = false

## Connected wallet address (empty if not connected)
var account_address: String = ""

## Current blockchain network ID (0 if not connected)
var chain_id: int = 0

# ============================================================================
# PRIVATE MEMBERS
# ============================================================================

## Reference to the JavaScript bridge object
var _js_bridge: JavaScriptObject = null

## Callback references (must be stored to prevent garbage collection)
var _accounts_changed_callback: JavaScriptObject = null
var _chain_changed_callback: JavaScriptObject = null
var _transaction_receipt_callback: JavaScriptObject = null

## Promise callback references (CRITICAL: must store these!)
var _connect_wallet_callback: JavaScriptObject = null
var _read_contract_callback: JavaScriptObject = null
var _write_contract_callback: JavaScriptObject = null
var _signature_callback: JavaScriptObject = null

## Flag to check if we're running in web export
var _is_web_export: bool = false

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	# Check if we're in a web export environment
	_is_web_export = OS.get_name() == "Web"
	
	if not _is_web_export:
		push_warning("[Web3Manager] Not running in web export. Web3 features disabled.")
		return
	
	# Get reference to the JavaScript bridge object
	_js_bridge = JavaScriptBridge.get_interface("GodotWeb3")
	
	if _js_bridge == null:
		push_error("[Web3Manager] Failed to get GodotWeb3 interface. Is the custom HTML shell configured correctly?")
		return
	
	# Create callbacks for JavaScript to call back into Godot
	_accounts_changed_callback = JavaScriptBridge.create_callback(_on_accounts_changed_js)
	_chain_changed_callback = JavaScriptBridge.create_callback(_on_chain_changed_js)
	_transaction_receipt_callback = JavaScriptBridge.create_callback(_on_transaction_receipt_js)
	
	# Create Promise callbacks (CRITICAL FIX)
	_connect_wallet_callback = JavaScriptBridge.create_callback(_on_connect_wallet_result)
	_read_contract_callback = JavaScriptBridge.create_callback(_on_read_contract_result)
	_write_contract_callback = JavaScriptBridge.create_callback(_on_write_contract_result)
	_signature_callback = JavaScriptBridge.create_callback(_on_signature_result)
	
	# Initialize the JavaScript bridge with our callbacks
	var callbacks = JavaScriptBridge.create_object("Object")
	callbacks.accountsChanged = _accounts_changed_callback
	callbacks.chainChanged = _chain_changed_callback  
	callbacks.transactionReceipt = _transaction_receipt_callback

	# The JavaScript 'initialize' function is synchronous
	var init_result = _js_bridge.initialize(callbacks)
	_on_initialize_result(init_result)

func _on_initialize_result(init_result: Variant) -> void:
	if _is_error_result(init_result):
		push_warning("[Web3Manager] Initialization warning: " + str(init_result.message))
	else:
		print("[Web3Manager] Successfully initialized")

# ============================================================================
# HELPER: Convert GDScript Dictionary to JavaScript Object
# ============================================================================

## CRITICAL: GDScript Dictionaries don't automatically convert to JS objects
## This function manually creates a JavaScript object and copies properties
func _dict_to_js_object(dict: Dictionary) -> JavaScriptObject:
	var js_obj = JavaScriptBridge.create_object("Object")
	for key in dict.keys():
		var value = dict[key]
		# Handle nested dictionaries and arrays
		if value is Dictionary:
			js_obj[key] = _dict_to_js_object(value)
		elif value is Array:
			js_obj[key] = _array_to_js_array(value)
		else:
			js_obj[key] = value
	return js_obj

## Convert GDScript Array to JavaScript Array
func _array_to_js_array(arr: Array) -> JavaScriptObject:
	var js_array = JavaScriptBridge.create_object("Array")
	for item in arr:
		if item is Dictionary:
			js_array.push(_dict_to_js_object(item))
		elif item is Array:
			js_array.push(_array_to_js_array(item))
		else:
			js_array.push(item)
	return js_array

# ============================================================================
# PUBLIC API - WALLET MANAGEMENT
# ============================================================================

## Connect to user's browser wallet (e.g., MetaMask)
## Emits: wallet_connected(address, chain_id) on success, web3_error() on failure
func connect_wallet() -> void:
	if not _check_web_export():
		return
	
	print("[Web3Manager] Requesting wallet connection...")
	
	var promise = _js_bridge.connect_wallet_js()
	promise.then(_connect_wallet_callback)

func _on_connect_wallet_result(args: Array) -> void:
	if args.size() == 0:
		push_error("[Web3Manager] Connect wallet callback received empty args")
		return
	
	var result = args[0]
	
	if _is_error_result(result):
		_emit_error(result)
		return
	
	# Update state
	account_address = result.address
	chain_id = result.chainId
	is_wallet_connected = true
	
	print("[Web3Manager] Connected to: ", account_address)
	wallet_connected.emit(account_address, chain_id)

## Disconnect wallet (updates state, doesn't force disconnect in MetaMask)
func disconnect_wallet() -> void:
	account_address = ""
	chain_id = 0
	is_wallet_connected = false
	wallet_disconnected.emit()
	print("[Web3Manager] Disconnected")

# ============================================================================
# PUBLIC API - SMART CONTRACT INTERACTION
# ============================================================================

## Generic function to call any smart contract function
func call_contract(params: Dictionary) -> void:
	if not _check_connection():
		return
	
	# Validate required parameters
	if not params.has("address") or not params.has("abi") or not params.has("function_name"):
		_emit_error_dict(-1, "Missing required parameters: address, abi, function_name", "call_contract")
		return
	
	# Ensure args exists
	if not params.has("args"):
		params["args"] = []
	
	# Ensure call_id exists for correlation
	if not params.has("call_id"):
		params["call_id"] = ""
	
	var is_write: bool = params.get("is_write", false)
	
	if is_write:
		_call_write_contract(params)
	else:
		_call_read_contract(params)

## Helper: Read from ERC-20 token balance
func get_erc20_balance(token_address: String, owner_address: String, call_id: String = "erc20_balance") -> void:
	var abi = '[{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"stateMutability":"view","type":"function"}]'
	
	call_contract({
		"address": token_address,
		"abi": abi,
		"function_name": "balanceOf",
		"args": [owner_address],
		"is_write": false,
		"call_id": call_id
	})

## Helper: Read ERC-20 allowance
func get_erc20_allowance(token_address: String, owner_address: String, spender_address: String, call_id: String = "erc20_allowance") -> void:
	var abi = '[{"constant":true,"inputs":[{"name":"_owner","type":"address"},{"name":"_spender","type":"address"}],"name":"allowance","outputs":[{"name":"remaining","type":"uint256"}],"stateMutability":"view","type":"function"}]'
	
	call_contract({
		"address": token_address,
		"abi": abi,
		"function_name": "allowance",
		"args": [owner_address, spender_address],
		"is_write": false,
		"call_id": call_id
	})

## Helper: Approve ERC-20 token spending
func approve_erc20(token_address: String, spender_address: String, amount_wei: String) -> void:
	var abi = '[{"constant":false,"inputs":[{"name":"_spender","type":"address"},{"name":"_value","type":"uint256"}],"name":"approve","outputs":[{"name":"success","type":"bool"}],"stateMutability":"nonpayable","type":"function"}]'
	
	call_contract({
		"address": token_address,
		"abi": abi,
		"function_name": "approve",
		"args": [spender_address, amount_wei],
		"is_write": true
	})

## Helper: Get ERC-721 NFT owner
func get_erc721_owner(token_address: String, token_id: String, call_id: String = "erc721_owner") -> void:
	var abi = '[{"constant":true,"inputs":[{"name":"tokenId","type":"uint256"}],"name":"ownerOf","outputs":[{"name":"owner","type":"address"}],"stateMutability":"view","type":"function"}]'
	
	call_contract({
		"address": token_address,
		"abi": abi,
		"function_name": "ownerOf",
		"args": [token_id],
		"is_write": false,
		"call_id": call_id
	})

## Helper: Get ERC-721 token balance
func get_erc721_balance(token_address: String, owner_address: String, call_id: String = "erc721_balance") -> void:
	var abi = '[{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"stateMutability":"view","type":"function"}]'
	
	call_contract({
		"address": token_address,
		"abi": abi,
		"function_name": "balanceOf",
		"args": [owner_address],
		"is_write": false,
		"call_id": call_id
	})

# ============================================================================
# PUBLIC API - TRANSACTIONS & SIGNING
# ============================================================================

## Send native blockchain currency (ETH, MATIC, etc.)
func send_native_token(to_address: String, value_wei: String) -> void:
	if not _check_connection():
		return
	
	print("[Web3Manager] Sending native token to: ", to_address)
	
	# CRITICAL FIX: Create JavaScript object properly
	var js_params = JavaScriptBridge.create_object("Object")
	js_params.to = to_address
	js_params.valueWei = value_wei
	
	var promise = _js_bridge.sendNativeToken(js_params)
	promise.then(_write_contract_callback)

## Sign a personal message for authentication or verification
func sign_personal_message(message: String) -> void:
	if not _check_connection():
		return
	
	print("[Web3Manager] Requesting message signature...")
	
	# CRITICAL FIX: Create JavaScript object properly
	var js_params = JavaScriptBridge.create_object("Object")
	js_params.message = message
	
	var promise = _js_bridge.signPersonalMessage(js_params)
	promise.then(_signature_callback)

## Sign typed data (EIP-712) for meta-transactions/gasless operations
func sign_meta_transaction(domain: Dictionary, types: Dictionary, value: Dictionary, primary_type: String) -> void:
	if not _check_connection():
		return
	
	print("[Web3Manager] Requesting typed data signature...")
	
	# Convert dictionaries to JSON strings for JavaScript
	var domain_json = JSON.stringify(domain)
	var types_json = JSON.stringify(types)
	var value_json = JSON.stringify(value)
	
	# CRITICAL FIX: Create JavaScript object properly
	var js_params = JavaScriptBridge.create_object("Object")
	js_params.domain = domain_json
	js_params.types = types_json
	js_params.value = value_json
	js_params.primaryType = primary_type
	
	var promise = _js_bridge.signTypedData(js_params)
	promise.then(_signature_callback)

# ============================================================================
# PRIVATE IMPLEMENTATION & RESULT HANDLERS
# ============================================================================

## Internal: Handle read-only contract calls
func _call_read_contract(params: Dictionary) -> void:
	# CRITICAL FIX: Convert Dictionary to JavaScript Object
	var js_params = _dict_to_js_object(params)
	var promise = _js_bridge.readContract(js_params)
	promise.then(_read_contract_callback)

func _on_read_contract_result(args: Array) -> void:
	if args.size() == 0:
		return
	
	var result = args[0]
	
	if _is_error_result(result):
		_emit_error(result)
		return
	
	contract_read_result.emit(result.result, result.callId)

## Internal: Handle state-changing contract calls
func _call_write_contract(params: Dictionary) -> void:
	# CRITICAL FIX: Convert Dictionary to JavaScript Object
	var js_params = _dict_to_js_object(params)
	var promise = _js_bridge.writeContract(js_params)
	promise.then(_write_contract_callback)

func _on_write_contract_result(args: Array) -> void:
	if args.size() == 0:
		return
	
	var result = args[0]
	
	if _is_error_result(result):
		_emit_error(result)
		return
	
	print("[Web3Manager] Transaction sent: ", result.hash)
	transaction_response.emit(result.hash)

## Internal: Handle signature results
func _on_signature_result(args: Array) -> void:
	if args.size() == 0:
		return
	
	var result = args[0]
	
	if _is_error_result(result):
		_emit_error(result)
		return
	
	print("[Web3Manager] Signature successful")
	signature_successful.emit(result.signature, result.originalData)

## Check if we're running in web export
func _check_web_export() -> bool:
	if not _is_web_export:
		push_error("[Web3Manager] Web3 operations only available in web exports")
		_emit_error_dict(-1, "Not running in web export", "check_export")
		return false
	return true

## Check if wallet is connected
func _check_connection() -> bool:
	if not _check_web_export():
		return false
	
	if not is_wallet_connected:
		push_error("[Web3Manager] Wallet not connected. Call connect_wallet() first.")
		_emit_error_dict(-3, "Wallet not connected", "check_connection")
		return false
	
	return true

## Check if a JavaScript result is an error
func _is_error_result(result: Variant) -> bool:
	if result is Dictionary:
		return result.get("error", false)
	return false

## Emit a web3_error signal from a JavaScript error result
func _emit_error(error_result: Dictionary) -> void:
	var code = error_result.get("code", -999)
	var message = error_result.get("message", "Unknown error")
	var op_id = error_result.get("operationId", "")
	
	push_error("[Web3Manager] Error (%d): %s" % [code, message])
	web3_error.emit(code, message, op_id)

## Emit a web3_error signal from custom values
func _emit_error_dict(code: int, message: String, operation_id: String) -> void:
	push_error("[Web3Manager] Error (%d): %s" % [code, message])
	web3_error.emit(code, message, operation_id)

# ============================================================================
# JAVASCRIPT CALLBACKS
# ============================================================================

## Called by JavaScript when accounts change in wallet
func _on_accounts_changed_js(args: Array) -> void:
	if args.size() == 0:
		return
	
	var new_account = args[0]
	
	if new_account == null or new_account == "":
		# Account disconnected
		account_address = ""
		is_wallet_connected = false
		print("[Web3Manager] Account disconnected")
		wallet_disconnected.emit()
	else:
		# Account changed
		account_address = new_account
		print("[Web3Manager] Account changed to: ", account_address)
		account_changed.emit(account_address)

## Called by JavaScript when chain changes in wallet
func _on_chain_changed_js(args: Array) -> void:
	if args.size() == 0:
		return
	
	var new_chain_id = args[0]
	chain_id = new_chain_id
	
	print("[Web3Manager] Chain changed to: ", chain_id)
	chain_changed.emit(chain_id)

## Called by JavaScript when transaction receipt is available
func _on_transaction_receipt_js(args: Array) -> void:
	if args.size() == 0:
		return
	
	var receipt = args[0]
	print("[Web3Manager] Transaction receipt received: ", receipt.get("transactionHash", ""))
	transaction_receipt.emit(receipt)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

## Convert wei (smallest unit) to ether/native token for display
func wei_to_float(wei_string: String, decimals: int = 18) -> float:
	var wei_value = float(wei_string)
	var divisor = pow(10.0, decimals)
	return wei_value / divisor

## Convert ether/native token to wei (smallest unit) for transactions
func float_to_wei(amount: float, decimals: int = 18) -> String:
	var multiplier = pow(10.0, decimals)
	var wei_value = amount * multiplier
	var wei_string = str(int(wei_value))
	return wei_string

## Format address for display (0x1234...5678)
func format_address_short(address: String) -> String:
	if address.length() < 10:
		return address
	return address.substr(0, 6) + "..." + address.substr(address.length() - 4, 4)

## Validate Ethereum address format (basic check)
func is_valid_address(address: String) -> bool:
	if not address.begins_with("0x"):
		return false
	if address.length() != 42:
		return false
	var hex_part = address.substr(2)
	for i in range(hex_part.length()):
		var c = hex_part[i]
		if not (c in "0123456789abcdefABCDEF"):
			return false
	return true
