extends Node
class_name IPFinder 
const STUN_SERVER_LIST = "https://raw.githubusercontent.com/pradt2/always-online-stun/master/valid_hosts.txt"

var Address: PackedInt32Array
var Port: int

enum IPFinderError {SUCCESS,
					STUN_SERVER_LIST_FETCH_FAILED,
					STUN_SERVER_LIST_FETCH_RESPONSE_NOT_OKAY,
					STUN_SERVER_ADDRESS_INVALID,
					STUN_GUN_FAILED_TO_SEND_STUN_REQUEST,
					STUN_GUN_RECIEVED_PACKET_TOO_SMALL,
					STUN_GUN_RECIEVED_NOT_A_BINDING_RESPONSE,
					STUN_GUN_RECIEVED_TRANSACTION_ID_MISMATCH,
					STUN_GUN_RECIEVED_ONLY_IPV4_SUPPORTED}
signal ip_finding_finished(result: IPFinderError)

func _ready() -> void:
	var http_req := HTTPRequest.new()
	add_child(http_req)
	http_req.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			if result        != HTTPRequest.Result.RESULT_SUCCESS  : printerr("request failed: "        , result)       ; return
			if response_code != HTTPClient.ResponseCode.RESPONSE_OK: printerr("response code not okay: ", response_code); return
			
			var stun_server_list: PackedStringArray = body.get_string_from_utf8().split("\n")
			var rand: int = int(floor(randf()*(stun_server_list.size()-1)))
			var stun_addr: PackedStringArray = stun_server_list[rand].split(":")
			
			if stun_addr.size() != 2: printerr("stun_addr must be an domain/port combo: ", stun_addr); return
			var server_requester: StunGun = StunGun.new(stun_addr[0], int(stun_addr[1]))
			add_child(server_requester)
			server_requester.ip_found.connect(
				func(external_ip: PackedInt32Array, external_port: int):
					Address = external_ip
					Port = external_port
					ip_finding_finished.emit(IPFinderError.SUCCESS)
					server_requester.queue_free()
			)
			http_req.queue_free()
	)
	http_req.request(STUN_SERVER_LIST)

func _get_ip_address() -> Dictionary:
	if Address.size() == 0 or Port == 0: 
		return {}
	else:
		queue_free()
		return {"ADDRESS": Address, "PORT": Port}

class StunGun extends Node:
	var udp := PacketPeerUDP.new()
	var transaction_id := PackedByteArray()
	
	signal ip_found(external_ip: PackedInt32Array, external_port: int)
	
	func _init(stun_addr: String, stun_port: int, local_port: int = 0) -> void:
		var bind_err = udp.bind(local_port)
		if bind_err != OK: printerr("Failed to bind UDP socket"); return
		udp.set_dest_address(stun_addr, stun_port)
		
		var packet = PackedByteArray()
		packet.append(0x00)
		packet.append(0x01)
		packet.append(0x00)
		packet.append(0x00)
		packet.append(0x21)
		packet.append(0x12)
		packet.append(0xA4)
		packet.append(0x42)
		# Transaction ID (12 random bytes)
		transaction_id = PackedByteArray()
		for i in range(12): transaction_id.append(randi() % 256)
		packet.append_array(transaction_id)
		
		# Send the packet
		var send_err = udp.put_packet(packet)
		if send_err != OK: printerr("Failed to send STUN request")

	func _process(_delta: float) -> void:
		if udp.get_available_packet_count() > 0:
			var response = udp.get_packet()
			parse_stun_response(response)

	func parse_stun_response(packet: PackedByteArray):
		if packet.size() < 20: printerr("Packet too small"); return
		var msg_type = (packet[0] << 8) | packet[1]
		if msg_type != 0x0101: printerr("Not a binding response"); return
		
		# Verify transaction ID matches
		var response_tid = packet.slice(8, 20)
		if response_tid != transaction_id: printerr("Transaction ID mismatch"); return
		
		# Parse attributes
		var offset = 20  # Start after header
		while offset < packet.size():
			if offset + 4 > packet.size():
				break
			
			var attr_type = (packet[offset] << 8) | packet[offset + 1]
			var attr_length = (packet[offset + 2] << 8) | packet[offset + 3]
			offset += 4
			
			if offset + attr_length > packet.size():
				break
			
			# XOR-MAPPED-ADDRESS (0x0020) - what we want
			if attr_type == 0x0020:
				parse_xor_mapped_address(packet, offset, attr_length)
				break
			
			# MAPPED-ADDRESS (0x0001) - fallback
			elif attr_type == 0x0001:
				parse_mapped_address(packet, offset, attr_length)
				break
			
			# Move to next attribute (padding to 4-byte boundary)
			offset += attr_length
			while offset % 4 != 0:
				offset += 1

	func parse_xor_mapped_address(packet: PackedByteArray, offset: int, length: int):
		if length < 8: return
		if packet[offset + 1] != 0x01: printerr("Only IPv4 supported"); return
		var external_ip = PackedInt32Array([
			packet[offset + 4] ^ 0x21,
			packet[offset + 5] ^ 0x12,
			packet[offset + 6] ^ 0xA4,
			packet[offset + 7] ^ 0x42
		])
		var external_port: int = (packet[offset + 2] << 8) | packet[offset + 3] ^ 0x2112
		ip_found.emit(external_ip, external_port)

	func parse_mapped_address(packet: PackedByteArray, offset: int, length: int):
		if length < 8: return
		if packet[offset + 1] != 0x01: printerr("Only IPv4 supported"); return
		var external_ip := PackedInt32Array([
			packet[offset + 4],
			packet[offset + 5],
			packet[offset + 6],
			packet[offset + 7]
		])
		var external_port: int = (packet[offset + 2] << 8) | packet[offset + 3]
		ip_found.emit(external_ip, external_port)
