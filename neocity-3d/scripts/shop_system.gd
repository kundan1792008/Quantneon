## Shop System (REST Client for Neo City Economy)
## Handles fetching shop items and making purchases.

extends Node

const SHOP_API_URL = "http://localhost:3000/v1/world/shop"

signal shop_opened(items)
signal purchase_result(success, message)

var http_request: HTTPRequest = null
var current_user_id: String = "local_user" # Should be synced from Auth

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func open_shop():
	print("[Shop] Fetching items...")
	var error = http_request.request(SHOP_API_URL)
	if error != OK:
		print("[Shop] Error fetching: ", error)

func buy_item(item_id: String):
	print("[Shop] Purchasing: ", item_id)
	var url = SHOP_API_URL + "/buy"
	var body = JSON.stringify({
		"userId": current_user_id,
		"itemId": item_id
	})
	var headers = ["Content-Type: application/json"]
	http_request.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_request_completed(result, response_code, headers, body):
	var response = JSON.parse_string(body.get_string_from_utf8())
	
	if response_code == 200:
		if response is Array:
			# It's the item list
			shop_opened.emit(response)
			if has_node("/root/ShopUI"):
				get_node("/root/ShopUI").display_items(response)
		else:
			# It's a purchase result
			purchase_result.emit(true, "Purchase successful!")
			if has_node("/root/ShopUI"):
				get_node("/root/ShopUI").update_balance(response.newBalance)
	else:
		var err_msg = "Error"
		if response and response.has("error"):
			err_msg = response.error
		purchase_result.emit(false, err_msg)
		if has_node("/root/ShopUI"):
			get_node("/root/ShopUI").show_error(err_msg)
