extends Node
class_name Pingus

var udp := PacketPeerUDP.new()
var random_sauce := PackedByteArray()

func _init(local_port: int = 0) -> void:
	var bind_err = udp.bind(local_port)
	if bind_err != OK: printerr("Pingus failed to bind UDP socket"); return

func _process(_delta: float) -> void:
	if udp.get_available_packet_count() > 0:
		var response = udp.get_packet()
		print("PINGUS RECIEVED!!!\n", response)

func _send_a_pingus(ping_addr: String, ping_port: int) -> void:
	udp.set_dest_address(ping_addr, ping_port)
	
	var packet = PackedByteArray()
	packet.append(0x00)
	packet.append(0x01)
	packet.append(0x02)
	packet.append(0x03)
	
	packet.append(0x04)
	packet.append(0x05)
	packet.append(0x06)
	packet.append(0x07)
	
	packet.append(0x08)
	packet.append(0x09)
	packet.append(0x0A)
	packet.append(0x0B)
	
	packet.append(0x0C)
	packet.append(0x0D)
	packet.append(0x0E)
	packet.append(0x0F)
	
	random_sauce = PackedByteArray()
	for i in range(12): random_sauce.append(randi() % 256)
	packet.append_array(random_sauce)
	
	# Send the packet
	var send_err = udp.put_packet(packet)
	if send_err != OK: printerr("Failed to send pingus")
	else: print("sending packet to ", ping_addr, ":", ping_port)
