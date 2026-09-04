extends Node
class_name OneTruePingus
## utility class for managing and communicating with an arbitrary amount of 
## multiplayer connections.[br][br]
## see also: [br]
## [OneTruePingus.AddressGopher][br]
## [OneTruePingus.PingusPeer]
## [codeblock]
## WORK LEFT TO DO:
## 1. enable LAN/WAN cross connections
## 2. remove Herobrine
## [/codeblock]

# ========= #
# constants #
# ========= #
## the only reserved data type. used internally when sending control data through [method send_data]
enum  DataTypes    {CONTROL = 0xC0}
## the current state of the connection to each peer
enum  PingusStates {NOT_STARTED, INFORMING, CONNECTED}
## the type of pingus being sent/recieved. used internally
enum  PingusTypes  {INFORM = 0x1EF0, KEEPALIVE = 0x8EE9, DATA = 0xDA7A}
## size in bytes of a [member NetworkID]. see [constant HEADER_SIZE]
const NETWORK_ID_SIZE : int   = 4
## size in bytes of a [OneTruePingus.PingusPeer]'s network port
const PORT_SIZE       : int   = 2
## size in bytes of user defined data types. see [method send_data] and [signal recieved_data]
const DATA_TYPE_SIZE  : int   = 1
## size in bytes of the internally defined and used [enum PingusTypes]. 
const PINGUS_TYPE_SIZE: int   = 2
## header layout: [lb]pkt [enum PingusType] u16[rb][lb]sender's [member NetworkID]
## u32[rb][lb]target's [member NetworkID] u32[rb][br] target 0 means "anyone" 
## (before the peer's ID is known).
const HEADER_SIZE     : int   = PINGUS_TYPE_SIZE + NETWORK_ID_SIZE + NETWORK_ID_SIZE
const _RETRY_TIME     : float = 0.5
const _MAX_RETRIES    : int   = 5
const _KEEP_ALIVE_TIME: float = 5.0
const _TIMEOUT_TIME   : float = 60.0
const _TWO_GENERALS   : int   = 0x26E1
# ========= #
# variables #
# ========= #
## all connected [OneTruePingus.PingusPeer]s
var Peers      : Array[PingusPeer] = []
## the external facing address on our router
var ExternAddr : String            = "":
   set(new_addr):
      var rx = RegEx.new()
      rx.compile("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$|PEE.POO.CUM.POO")
      if rx.search(new_addr): ExternAddr = new_addr
## the external facing port on our router
var ExternPort : int               = -1:
   set(new_port):
      var rx = RegEx.new()
      rx.compile("^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$")
      if rx.search(str(new_port)): ExternPort = new_port
## a unique ID to differentiate our traffic on the network
var NetworkID  : int               = 0
## the local address we are sending from. [b]READONLY[/b]
var LocalAddr  : String            = "":
   set(new_val): LocalAddr = new_val
   get():
      for address in IP.get_local_addresses():
         if address.begins_with("192.168"):
            LocalAddr = address
            return address
      return "PEE.POO.CUM.POO" 
## the local port we are sending from. [b]READONLY[/b]
var LocalPort  : int               = 0:
   set(new_val): LocalPort = new_val
   get(): 
      LocalPort = _Udp.get_local_port()
      return _Udp.get_local_port()
var _Udp            : PacketPeerUDP     = PacketPeerUDP.new()
var _SprayRate      : int               = 100
var _RetryCount     : int               = 0
var _FetchingAddress: bool              = false
# ======= #
# signals #
# ======= #
## emitted when a packet or control signal is recieved. if it is an internal control 
## signal, [param data_type] will be [enum DataTypes].CONTROL and [param data] 
## will be a [String]. in all other cases, [b][param data_type] should be an enum
## value defined by the application using OneTruePingus[/b][br]see [constant DATA_TYPE_SIZE]
## and [constant HEADER_SIZE]
signal recieved_data(sender_id: int, data_type: int, data: PackedByteArray)
## emitted when a [OneTruePingus.PingusPeer] reaches the [enum PingusStates].CONNECTED status
signal connection_established(sender_id: int, address: String, port: int)
# ===== #
# setup #
# ===== #
func _init(external_address: String = "", network_id: int = 0, custom_stun_addr: String = "") -> void:
   NetworkID = network_id
   ExternAddr = external_address
   var bind_err = _Udp.bind(0)
   if bind_err != OK: _emit_control("ERROR: OneTruePingus failed to bind UDP socket"); return
   if NetworkID  == 0: _discover_network_id()
   if ExternAddr == "": _discover_address(custom_stun_addr)
func _discover_network_id() -> void:
   while NetworkID == 0:
      seed(((Time.get_unix_time_from_system()*100000)+_Udp.get_local_port()) as int)
      NetworkID = randi()
func _discover_address(custom_stun_addr: String = "") -> void:
   _FetchingAddress = true
   var ag := AddressGopher.new(_Udp, custom_stun_addr)

   ag.info_fetching_complete.connect(
      func(result: AddressGopher.InfoFetchingResults, address: String = "", port: int = 0):
         var retry_on_fail: Callable = func(err_str: String):
            _RetryCount += 1
            if _RetryCount < _MAX_RETRIES:
               _emit_control(err_str + " Retrying...")
               await get_tree().create_timer(_RETRY_TIME).timeout
               ag.attempt_info_fetch()
            else:
               _FetchingAddress = false
               _emit_control(err_str + " Aborting...")
         match result:
            AddressGopher.InfoFetchingResults.OK:
               _FetchingAddress = false
               ExternAddr = address
               ExternPort = port
               _emit_control("External address: " + ExternAddr + ":" + str(ExternPort))
            AddressGopher.InfoFetchingResults.BAD_SERVER_LIST_RESULT  : retry_on_fail.call("BAD_SERVER_LIST_RESULT")
            AddressGopher.InfoFetchingResults.BAD_SERVER_LIST_RESPONSE: retry_on_fail.call("BAD_SERVER_LIST_RESPONSE")
            AddressGopher.InfoFetchingResults.BAD_SERVER_LIST_DATA    : retry_on_fail.call("BAD_SERVER_LIST_DATA")
            AddressGopher.InfoFetchingResults.BAD_STUN_RESULT         : retry_on_fail.call("BAD_STUN_RESULT")
            AddressGopher.InfoFetchingResults.BAD_STUN_RESPONSE       : retry_on_fail.call("BAD_STUN_RESPONSE")
            AddressGopher.InfoFetchingResults.BAD_STUN_DATA           : retry_on_fail.call("BAD_STUN_DATA")
   )
   ag.set_name("AddressGopher")
   add_child(ag)
# =============== #
# actual function #
# =============== #
## get our own IP:Port combo as a [String]. defaults to WAN. set [param external]
## false to get the LAN values. 
func get_addr_port(external: bool = true) -> String:
   if external: return ExternAddr + ":" + (str(ExternPort) if ExternAddr != "PEE.POO.CUM.POO" else "WEINER" )
   else: return LocalAddr + ":" + (str(LocalPort) if LocalAddr != "PEE.POO.CUM.POO" else "WEINER" )
## add a IP:Port to target communications with. 
func add_peer(target_addr: String, target_port: int, target_id: int = 0) -> void:
   if target_id != 0 and target_id == NetworkID: return
   for old_peer in Peers:
      if target_id != 0 and old_peer.NetworkID == target_id: return
      if old_peer.Addr == target_addr and old_peer.Port == target_port: return
   var peer   := PingusPeer.new(target_addr, target_port, target_id)
   peer.State  = PingusStates.INFORMING
   Peers.append(peer)
   _emit_control("Attempting to connect to " + target_addr + ":" + str(target_port))
func _process(delta: float) -> void:
   if ExternAddr == "" or ExternPort == -1 or NetworkID == 0: return

   # handle incoming packets
   while not _FetchingAddress and _Udp.get_available_packet_count() > 0:
      var pkt       := _Udp.get_packet()
      var from_addr  = _Udp.get_packet_ip()
      var from_port  = _Udp.get_packet_port()
      if Peers.is_empty(): continue
      # decode and validate packet
      if pkt.size() < HEADER_SIZE: _emit_control("ERROR: undersized packet"); continue
      var pkt_type : int = pkt.decode_u16(0)
      var sender_id: int = pkt.decode_u32(PINGUS_TYPE_SIZE)
      var target_id: int = pkt.decode_u32(PINGUS_TYPE_SIZE + NETWORK_ID_SIZE)
      if (from_addr == ExternAddr and from_port == ExternPort) or (from_addr == LocalAddr and from_port == LocalPort) or (sender_id == NetworkID): continue
      if target_id != 0 and target_id != NetworkID: continue
      # locate peer
      var peer = _find_peer(from_addr, from_port, sender_id)
      if peer == null: _emit_control("ERROR: packet from unknown peer " + from_addr + ":" + str(from_port)); continue
      if peer.NetworkID == 0 and sender_id != 0: peer.NetworkID = sender_id
      # handle packet
      match peer.State:
         PingusStates.INFORMING:
            if pkt_type != PingusTypes.INFORM: _emit_control("ERROR: incorrect packet type while informing"); continue
            if pkt.size() < HEADER_SIZE + PORT_SIZE: _emit_control("ERROR: INFORM packet too small for port"); continue
            peer.State = PingusStates.CONNECTED
            peer.TimeSincePkt = 0.0
            _emit_control("Established connection to " + str(sender_id) + " (" + from_addr + ":" + str(from_port) + ")", sender_id)
            _inform_peer(peer, delta)
            connection_established.emit(sender_id, from_addr, from_port)
         PingusStates.CONNECTED:
            if from_addr != peer.Addr or from_port != peer.Port: _emit_control("ERROR: packet from unidentified source"); continue
            if sender_id != peer.NetworkID or (target_id != 0 and target_id != NetworkID): _emit_control("ERROR: packet signed by unidentified sender"); continue
            match pkt_type:
               PingusTypes.KEEPALIVE: _emit_control(str(sender_id) + " (" + peer.Addr + ":" + str(peer.Port) + ") is keeping connection alive", sender_id)
               PingusTypes.INFORM:
                  _emit_control(str(sender_id) + " (" + peer.Addr + ":" + str(peer.Port) + ") re-confirmed connection", sender_id)
                  if pkt.size() <= HEADER_SIZE + PORT_SIZE:
                     _inform_peer(peer, delta, true)
                     _emit_control(str(sender_id) + " (" + peer.Addr + ":" + str(peer.Port) + ") is experiencing a two-generals problem", sender_id)
               PingusTypes.DATA:
                  if pkt.size() < HEADER_SIZE + DATA_TYPE_SIZE: _emit_control("ERROR: DATA packet missing type byte"); continue
                  recieved_data.emit(sender_id, pkt.decode_u8(HEADER_SIZE), pkt.slice(HEADER_SIZE + DATA_TYPE_SIZE))
                  peer.TimeSincePkt = 0.0
               _: _emit_control("ERROR: incorrect packet type while connected")
   
   # inform peers and keep connections alive
   for peer:PingusPeer in Peers:
      peer.TimeSincePkt += delta
      match peer.State:
         PingusStates.INFORMING:
            _inform_peer(peer, delta)
            if peer.TimeSincePkt >= _TIMEOUT_TIME:
               Peers.erase(peer)
               _emit_control("Attempt to establish connection to: " + peer.Addr + ":" + str(peer.Port) + " has timed out")
         PingusStates.CONNECTED:
            if peer.TimeSincePkt >= _KEEP_ALIVE_TIME:
               peer.TimeSincePkt -= _KEEP_ALIVE_TIME
               _keepalive_peer(peer)
func _find_peer(from_addr: String, from_port: int, sender_id: int) -> PingusPeer:
   if sender_id != 0:
      for peer in Peers:
         if peer.NetworkID == sender_id: return peer
   for peer in Peers:
      if peer.Addr == from_addr and peer.Port == from_port: return peer
   return null
 
# ============== #
# packet sending #
# ============== #
## send typed application data to all connected peers. data_type is a single byte.
## values other than [enum DataTypes].CONTROL (0xC0) are free for the application to define.
func send_data(data_type: int, data: PackedByteArray = PackedByteArray()) -> void:
   for peer in Peers:
      if peer.State != PingusStates.CONNECTED: continue
      _Udp.set_dest_address(peer.Addr, peer.Port)
      var pkt := _make_header(PingusTypes.DATA, peer)
      pkt.resize(HEADER_SIZE + DATA_TYPE_SIZE)
      pkt.encode_u8(HEADER_SIZE, data_type)
      pkt.append_array(data)
      var send_err = _Udp.put_packet(pkt)
      if send_err != OK: _emit_control("ERROR: failed to send data to " + peer.Addr + ":" + str(peer.Port))
func _make_header(pkt_type: PingusTypes, peer: PingusPeer) -> PackedByteArray:
   var hdr := PackedByteArray()
   hdr.resize(HEADER_SIZE)
   hdr.encode_u16(0, pkt_type)
   hdr.encode_u32(PINGUS_TYPE_SIZE, NetworkID)
   hdr.encode_u32(PINGUS_TYPE_SIZE + NETWORK_ID_SIZE, peer.NetworkID)
   return hdr
func _emit_control(msg: String, sender_id: int = 0) -> void:
   recieved_data.emit(sender_id if sender_id else NetworkID, DataTypes.CONTROL, msg.to_utf8_buffer())
func _inform_peer(peer: PingusPeer, delta: float, two_generals: bool = false) -> void:
   # PingusStates.INFORMING
   _Udp.set_dest_address(peer.Addr, peer.Port)
   var count := ceili(_SprayRate * delta)
   while count > 0:
      count -= 1
      var pkt := _make_header(PingusTypes.INFORM, peer)
      pkt.resize(HEADER_SIZE + PORT_SIZE)
      pkt.encode_u16(HEADER_SIZE, peer.Port)
      if two_generals: pkt.append(_TWO_GENERALS)
      var send_err = _Udp.put_packet(pkt)
      if send_err != OK: _emit_control("ERROR: failed to send inform to " + peer.Addr + ":" + str(peer.Port))
   _emit_control("Informing " + peer.Addr + " at port: " + str(peer.Port))
func _keepalive_peer(peer: PingusPeer) -> void:
   # PingusStates.CONNECTED
   _Udp.set_dest_address(peer.Addr, peer.Port)
   var send_err = _Udp.put_packet(_make_header(PingusTypes.KEEPALIVE, peer))
   if send_err != OK: _emit_control("ERROR: failed to send keepalive to " + peer.Addr + ":" + str(peer.Port))
   else: _emit_control("Preventing timeout with " + peer.Addr + ":" + str(peer.Port))

## data structure to store info about a peer. 
class PingusPeer:
   ## the IP address the [OneTruePingus] uses to connect to the peer. 
   var Addr         : String = ""
   ## the Port the [OneTruePingus] uses to connect to this peer
   var Port         : int    = -1
   ## the network ID of the peer. see [member OneTruePingus.NetworkID]
   var NetworkID    : int    = 0
   ## time elapsed since last packet. see [member OneTruePingus._KEEP_ALIVE_TIME] and [member OneTruePingus._TIMEOUT_TIME] (yeah those are both hidden properties i know lmao
   var TimeSincePkt : float  = 0.0
   ## the state of the connection between the [OneTruePingus] and the peer.
   var State  : PingusStates = PingusStates.NOT_STARTED
   func _init(addr: String, port: int, id: int) -> void:
      Addr      = addr
      Port      = port
      NetworkID = id
## utility class to fetch external facing IP/port combo.[br]
## underpinned by [url=https://github.com/pradt2/always-online-stun.git]pradt2's github[/url]. many thanks to them![br][br]
## [i]*writted by Claude Opus 4.8, so it might be straight dookie idk. i didn't feel like dealing with the complexities of the STUN protocol. sue me...[/i]
class AddressGopher extends Node:
   ## SERVER_LIST errors are involved with fetching the sever list from [url=https://github.com/pradt2/always-online-stun.git]pradt2's github[/url].[br]
   ## STUN errors are involved with contacting the actual STUN server.
   enum InfoFetchingResults {OK, BAD_SERVER_LIST_RESULT, BAD_SERVER_LIST_RESPONSE, BAD_SERVER_LIST_DATA, BAD_STUN_RESULT, BAD_STUN_RESPONSE, BAD_STUN_DATA }
   ## the route by which the info will return. ensure you connect  a handler to 
   ## this signal before adding the AddressGopher to the tree because this 
   ## [b]***will blow its own shit smooth off the moment it sends a [member InfoFetchingResults.OK]***[/b]
   signal info_fetching_complete(result: InfoFetchingResults, ip: String, port: int)
   ## [url=https://github.com/pradt2/always-online-stun.git]pradt2's github[/url] 
   ## from which we fetch a list of STUN servers
   const SERVER_LIST_URL   : String = "https://raw.githubusercontent.com/pradt2/always-online-stun/master/valid_hosts.txt"
   const _MAGIC_COOKIE     : int    = 0x2112A442
   ## see [member CustomStunUrl]
   const DEFAULT_STUN_PORT : int    = 3478
   ## the address of a specific STUN server to use instead of a random one fetched
   ## from [url=https://github.com/pradt2/always-online-stun.git]pradt2's github[/url].
   ## if no port is specified in the string, [constant DEFAULT_STUN_PORT] will be
   ## used instead.[br][br]see [method attempt_info_fetch]
   var   CustomStunUrl     : String          = ""
   var   _SharedUdp        : PacketPeerUDP   = null

   func _init(shared_udp: PacketPeerUDP, custom_stun_server_addr: String = "") -> void:
      _SharedUdp    = shared_udp
      CustomStunUrl = custom_stun_server_addr
   func _ready() -> void: attempt_info_fetch()
   ## typically, we will contact [url=https://github.com/pradt2/always-online-stun.git]pradt2's github[/url]
   ## for a list of active STUN servers, pick one at random, and ping it to discover
   ## our IP:Port.[br]
   ## in the unlikely event that github ever goes down, or you want to target a
   ## specific STUN server, simply set [member CustomStunUrl] to a valid STUN server.
   func attempt_info_fetch() -> void:
      var stun_server_url: String = CustomStunUrl
      if not stun_server_url: stun_server_url = await _fetch_stun_server_addr_from_github_repo()
      if not stun_server_url: return

      var parts := stun_server_url.rsplit(":", true, 1)
      var host: String = parts[0]
      var port: int    = int(parts[1]) if parts.size() > 1 else DEFAULT_STUN_PORT
      _stun_request(host, port)
   func _fetch_stun_server_addr_from_github_repo() -> String:
      var http := HTTPRequest.new()
      add_child(http)
      if http.request(SERVER_LIST_URL) != OK:
         info_fetching_complete.emit(InfoFetchingResults.BAD_SERVER_LIST_RESULT)
         http.queue_free()
         return ""

      var res: Array = await http.request_completed
      http.queue_free()
      var result: int          = res[0]
      var code:   int          = res[1]
      var data: PackedByteArray = res[3]

      if result != HTTPRequest.RESULT_SUCCESS: info_fetching_complete.emit(InfoFetchingResults.BAD_SERVER_LIST_RESULT);   return ""
      if code   != HTTPClient.RESPONSE_OK    : info_fetching_complete.emit(InfoFetchingResults.BAD_SERVER_LIST_RESPONSE); return ""

      var server_list = data.get_string_from_utf8().split("\n", false)
      if server_list.is_empty(): info_fetching_complete.emit(InfoFetchingResults.BAD_SERVER_LIST_DATA); return ""

      var entry: String = server_list[randi() % server_list.size()].strip_edges()
      return entry
   func _stun_request(host: String, port: int, timeout := 3.0) -> void:
      var ip: String = host
      if not host.is_valid_ip_address(): ip = IP.resolve_hostname(host, IP.TYPE_IPV4)
      if ip.is_empty(): info_fetching_complete.emit(InfoFetchingResults.BAD_STUN_RESULT); return

      _SharedUdp.set_dest_address(ip, port)

      var txn := PackedByteArray()
      for i in 12: txn.append(randi() & 0xFF)

      _SharedUdp.put_packet(_build_binding_request(txn))

      var elapsed := 0.0
      while elapsed < timeout:
         if _SharedUdp.get_available_packet_count() > 0:
            var packet   := _SharedUdp.get_packet()
            var pkt_ip    = _SharedUdp.get_packet_ip()
            var pkt_port  = _SharedUdp.get_packet_port()
            if pkt_ip != ip or pkt_port != port: continue
            var parsed := _parse_stun_response(packet)
            if not parsed.success:
               info_fetching_complete.emit(InfoFetchingResults.BAD_STUN_DATA); return
            info_fetching_complete.emit(InfoFetchingResults.OK, parsed.ip, parsed.port)
            self.queue_free()
            return
         await get_tree().create_timer(0.05).timeout
         elapsed += 0.05

      info_fetching_complete.emit(InfoFetchingResults.BAD_STUN_RESPONSE)
   func _build_binding_request(txn: PackedByteArray) -> PackedByteArray:
      var buf := StreamPeerBuffer.new()
      buf.big_endian = true
      buf.put_u16(0x0001)
      buf.put_u16(0x0000)
      buf.put_u32(_MAGIC_COOKIE)
      buf.put_data(txn)
      return buf.data_array
   func _parse_stun_response(resp: PackedByteArray) -> Dictionary:
      var fail := {"success": false, "ip": "", "port": 0}
      if resp.size() < 20: return fail

      var buf := StreamPeerBuffer.new()
      buf.data_array = resp
      buf.big_endian = true
      var msg_type := buf.get_u16()
      var _msg_len := buf.get_u16()
      var cookie   := buf.get_u32()
      if cookie != _MAGIC_COOKIE or msg_type != 0x0101:
         return fail

      var pos := 20
      while pos + 4 <= resp.size():
         buf.seek(pos)
         var attr_type := buf.get_u16()
         var attr_len  := buf.get_u16()
         var val := pos + 4
         if   attr_type == 0x0020: return _decode_addr(resp, val, true)
         elif attr_type == 0x0001: return _decode_addr(resp, val, false)
         pos = val + attr_len
         if attr_len % 4 != 0: pos += 4 - (attr_len % 4)
      return fail
   func _decode_addr(resp: PackedByteArray, i: int, xored: bool) -> Dictionary:
      var family := resp[i + 1]
      if family != 0x01: return {"success": false, "ip": "", "port": 0}
      var raw_port := (resp[i + PORT_SIZE] << 8) | resp[i + 3]
      var port := raw_port ^ (_MAGIC_COOKIE >> 16) if xored else raw_port
      var ck := [0x21, 0x12, 0xA4, 0x42]
      var o := []
      for k in 4:
         o.append((resp[i + 4 + k] ^ ck[k]) if xored else resp[i + 4 + k])
      return {"success": true, "ip": "%d.%d.%d.%d" % o, "port": port}
