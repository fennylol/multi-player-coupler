extends Node
class_name IPGopher

const IP_FETCHING_URL = "https://api.ipify.org"
var Address: PackedInt32Array
func get_address() -> PackedInt32Array: return Address
func get_address_as_string() -> String: return str(Address[0])+"."+str(Address[1])+"."+str(Address[2])+"."+str(Address[3])

enum IpFetchingErrs {OK, BAD_RESULT, BAD_RESPONSE, BAD_IP}
signal ip_fetching_finished(err: IpFetchingErrs)

func _ready()              -> void: _attempt_addr_fetch()
func _attempt_addr_fetch() -> void:
	var http_req := HTTPRequest.new()
	add_child(http_req)
	http_req.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			if result        != HTTPRequest.Result.RESULT_SUCCESS  : ip_fetching_finished.emit(IpFetchingErrs.BAD_RESULT)  ; http_req.queue_free(); return
			if response_code != HTTPClient.ResponseCode.RESPONSE_OK: ip_fetching_finished.emit(IpFetchingErrs.BAD_RESPONSE); http_req.queue_free(); return
			var IP_str: PackedStringArray = body.get_string_from_utf8().split(".")
			if IP_str.size() != 4                                  : ip_fetching_finished.emit(IpFetchingErrs.BAD_IP)      ; http_req.queue_free(); return
			Address = PackedInt32Array([int(IP_str[0]), int(IP_str[1]), int(IP_str[2]), int(IP_str[3])])
			ip_fetching_finished.emit(IpFetchingErrs.OK)
			http_req.queue_free()
	)
	http_req.request(IP_FETCHING_URL)
