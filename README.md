A Godot utility for managing an arbitrary number of UDP connections as a pure, relay-server-free peer-to-peer mesh.
Built directly on PacketPeerUDP rather than Godot’s high-level multiplayer API.

Sample project implements a simple chat room. 

Signals

- received_data(sender_id, data_type, data): emitted when a packet arrives. The data_type parameter is defined by the calling application, except for the reserved CONTROL type, which is used internally to repor status and diagnostics.
- connection_established(sender_id, address, port): emitted when a peer’s state changes to CONNECTED, meaning the handshake is complete.

Key methods

- add_peer(target_addr, target_port, target_id = 0): registers a peer for tracking and initiates the connection handshake.
- send_data(data_type, data): sends typed application data to every peer currently in the CONNECTED state.
- get_addr_port(external = true): returns the address and port of the local instance. external controls whether the external or local address is retured.

Key properties

- Peers: Array[PingusPeer]: all known peers, regardless of connection state.
- NetworkID: int: a randomly generated identifier that distinguishes this instance’s traffic on the network.
- ExternAddr / ExternPort: the externally-facing address and port of this instance, once discovered.
