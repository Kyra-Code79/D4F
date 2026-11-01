# Draw for Fight (D4F) — Multiplayer Networking Architecture (`NETWORKING.md`)

## 1. System Purpose
The Networking Subsystem (`NetworkManager`, `LANBroadcaster`, `RelayConnector`, `SnapshotInterpolator`) implements a self-hosted, authoritative Listen-Server multiplayer architecture over `ENetMultiplayerPeer`. It enables any player to host an 8-player room (Host = Authoritative Server + Local Player `Peer ID 1`) while up to 7 remote players join via zero-config LAN UDP Broadcast Discovery, Direct IP/Port, or an optional lightweight `RelayConnector` tunnel for NAT traversal—without requiring any dedicated cloud server infrastructure.

---

## 2. Functional Requirements
- **FR-NET-01**: Support 2 to 8 concurrent players in a single room with dual-role Host execution (`Peer ID = 1` runs both the authoritative 60 Hz physics/match server and a local client).
- **FR-NET-02**: Provide automatic zero-configuration LAN room discovery using periodic UDP broadcast beacons on port `42425`.
- **FR-NET-03**: Support Direct IPv4/IPv6 + Port (`42424` default) connection and an optional `RelayConnector` room-code fallback for symmetric NAT environments.
- **FR-NET-04**: Synchronize custom player creations (`CreationData`) and collaborative map deltas reliably over chunked ordered channels.
- **FR-NET-05**: Implement 60 Hz client-side input prediction with server reconciliation and 20 Hz snapshot interpolation (100 ms render delay buffer) for smooth remote entity motion.
- **FR-NET-06**: Support a 45-second disconnect grace window with cryptographic reconnection tickets so players who experience brief Wi-Fi drops can seamlessly rejoin an active match.

---

## 3. Non-Functional Requirements
- **Bandwidth Budget**:
  - Per-Client Upstream: $\le 18\text{ KB/s}$ during active 60 Hz gameplay.
  - Host Downstream/Upstream (8 Players): $\le 140\text{ KB/s}$ aggregate outbound bandwidth at 20 Hz snapshot broadcast rate.
- **Latency Tolerance**: Smooth, playable experience up to $150\text{ ms}$ RTT and $2\%$ UDP packet loss without rubber-banding or physics explosion.
- **Zero External Dependency**: Full LAN and Direct IP functionality operates 100% offline on an isolated local network.

---

## 4. Inputs and Outputs
- **Inputs**:
  - Host room configuration (`room_name`, `port`, `max_players`, `password`, `mode_id`).
  - Local 60 Hz player input frames (`move_vector`, `jump`, `primary_action`, `secondary_action`, `camera_yaw`).
  - Incoming UDP datagrams from `ENetMultiplayerPeer` and `PacketPeerUDP` discovery socket.
- **Outputs**:
  - Authenticated and decrypted gameplay packets routed to `MatchManager` and active entities.
  - Interpolated 3D transforms for remote players and reconciled local player physics state.
  - Real-time network telemetry (`rtt_ms`, `packet_loss_pct`, `jitter_ms`).

---

## 5. Components and Responsibilities

### 5.1 Core Network Components (`res://scripts/network/`)
1. **`NetworkManager` (`res://scripts/autoload/network_manager.gd`)**:
   - Manages the lifecycle of `ENetMultiplayerPeer` (`create_server`, `create_client`, `close`).
   - Allocates 3 distinct ENet communication channels to prevent head-of-line blocking:
     - **Channel 0 (`TRANSFER_MODE_RELIABLE`)**: 8-Layer Security Handshake, Lobby state, Match phase transitions, Scoreboard updates.
     - **Channel 1 (`TRANSFER_MODE_RELIABLE`)**: Chunked `CreationData` JSON uploads and Collaborative Map Editor delta commands.
     - **Channel 2 (`TRANSFER_MODE_UNRELIABLE_ORDERED`)**: 60 Hz Client Input frames (`PKT_CLIENT_INPUT`) and 20 Hz Authoritative World Snapshots (`PKT_WORLD_SNAPSHOT`).
2. **`LANDiscoveryService` (`res://scripts/network/lan_discovery_service.gd`)**:
   - **Host Broadcaster**: Binds a `PacketPeerUDP` with `set_broadcast_enabled(true)` and emits a signed JSON beacon to `255.255.255.255:42425` every $1.5\text{ seconds}$ containing `room_id`, `room_name`, `host_nickname`, `game_port`, `current_players`, `max_players`, `mode_name`, `requires_password`, and `protocol_version`.
   - **Client Listener**: Listens on UDP port `42425`, validates beacon schema, measures local ping, and prunes stale rooms after $4.5\text{ seconds}$ of silence.
3. **`RelayConnector` (`res://scripts/network/relay_connector.gd`)**:
   - Optional pluggable transport adapter that maps a human-readable 6-character alphanumeric **Room Code** (e.g., `D4F-8K2`) to a UDP hole-punching coordinator or lightweight packet forwarder.
   - Because all packets are end-to-end encrypted by `SecurityManager` (Layer 6 `AES-256-CBC` + `HMAC-SHA256`), the relay is completely untrusted and cannot inspect or forge game traffic.
4. **`SnapshotInterpolator` & `ClientPredictor` (`res://scripts/network/snapshot_interpolator.gd`)**:
   - **Local Player Prediction**: Stores a 128-entry ring buffer of `InputFrame` structs indexed by monotonic `seq_num`. Applies inputs immediately to the local `PlayableCharacter3D`/`PlayableVehicle3D`. Upon receiving `PKT_WORLD_SNAPSHOT` with `ack_seq`, compares historical predicted position against authoritative position; if error $\ge 0.05\text{m}$, rewinds and re-simulates unacknowledged inputs with a 4-frame exponential visual smoothing offset.
   - **Remote Entity Interpolation**: Maintains a $100\text{ ms}$ (2-snapshot) interpolation buffer for all remote entities, blending position via linear/Hermite interpolation and rotation via quaternion `slerp()`.

---

## 6. Internal Workflow (Host/Client Topology, Connection, Sync & Reconnection)
*(See also [`07_host_and_joining_player_architecture.md`](file:///C:/Personal%20Project/D4F/draw-for-fight/docs/diagrams/07_host_and_joining_player_architecture.md), [`08_multiplayer_connection_sequence.md`](file:///C:/Personal%20Project/D4F/draw-for-fight/docs/diagrams/08_multiplayer_connection_sequence.md), [`11_game_state_synchronization.md`](file:///C:/Personal%20Project/D4F/draw-for-fight/docs/diagrams/11_game_state_synchronization.md), and [`12_disconnect_and_reconnection_workflow.md`](file:///C:/Personal%20Project/D4F/draw-for-fight/docs/diagrams/12_disconnect_and_reconnection_workflow.md))*

```mermaid
sequenceDiagram
    autonumber
    participant Client as Joining Client (Peer N)
    participant Disc as LAN UDP Beacon (:42425)
    participant Host as Authoritative Host (Peer 1)

    Host->>Disc: Broadcast UDP Room Beacon (Every 1.5s)
    Disc-->>Client: Discover Room & Select Join
    Client->>Host: ENet Connect (:42424) -> Quarantine in PENDING_AUTH
    Host<-->Client: Execute 8-Layer Security Handshake (Channel 0)
    Host->>Client: Issue Encrypted ReconnectTicket & Lobby State
    Client->>Host: Upload Sanitized CreationData (Channel 1)
    Note over Host,Client: Active Match Loop (60 Hz Client Input / 20 Hz Server Snapshot)
    loop Every 16.67ms (60 Hz)
        Client->>Client: Predict Local Physics Step & Store InputFrame[Seq]
        Client->>Host: Send PKT_CLIENT_INPUT (Seq, Move, Actions) [Channel 2]
    end
    loop Every 50.0ms (20 Hz)
        Host->>Host: Step Authoritative Jolt Physics & Evaluate Mode Rules
        Host->>Client: Broadcast PKT_WORLD_SNAPSHOT (ServerTick, AckSeq, All Entity States) [Channel 2]
        Client->>Client: Reconcile Local Prediction & Interpolate Remote Entities (-100ms Buffer)
    end
```

---

## 7. Data Structures
- **`ClientInputPacket` (`PKT_CLIENT_INPUT`)**:
  ```gdscript
  {
      "t": 1,                        # PacketType.CLIENT_INPUT
      "seq": 1042,                   # Monotonic input sequence number
      "ack_snap": 340,               # Last received server snapshot ID
      "mv": [0.0, 1.0],              # Clamped 2D movement vector (x, z)
      "yaw": 1.5708,                 # Camera/Aim yaw angle (radians)
      "btn": 5                       # Bitmask: Bit0=Jump/Brake, Bit1=Attack/Boost, Bit2=Grab/Drift
  }
  ```
- **`WorldSnapshotPacket` (`PKT_WORLD_SNAPSHOT`)**:
  ```gdscript
  {
      "t": 2,                        # PacketType.WORLD_SNAPSHOT
      "snap_id": 341,                # Monotonic server snapshot ID
      "srv_ms": 84550,               # Server physics clock (ms)
      "acks": {2: 1042, 3: 998},     # Last processed input seq per Peer ID
      "entities": [
          {
              "id": 1,
              "p": [12.4, 1.05, -4.2],    # Position Vector3
              "q": [0.0, 0.707, 0.0, 0.707], # Rotation Quaternion
              "v": [0.0, 0.0, -8.5],      # Linear Velocity Vector3
              "st": 0                     # State flags (Grounded, Knockback, Respawning)
          }
      ]
  }
  ```

---

## 8. Dependencies
- Godot `ENetMultiplayerPeer`, `ENetConnection`, `PacketPeerUDP`.
- `SecurityManager` (mandatory packet encryption/decryption wrapper).
- `D4FSerializer` (binary/JSON quantization and NaN/Inf sanitization).

---

## 9. Error Handling
- **Transient Disconnect & 45s Reconnection Grace Window**:
  - When a client's heartbeat times out ($> 5.0\text{s}$), `NetworkManager` does **not** immediately destroy their player slot. Instead, the slot enters `DISCONNECTED_RESERVED` for $45.0\text{ seconds}$.
  - The client automatically retries connecting with exponential backoff ($1\text{s}, 2\text{s}, 4\text{s}, 8\text{s}$) presenting its HMAC-signed `ReconnectTicket`.
  - Upon verification, the Host binds the new ENet `peer_id` to the reserved player slot and sends a full catch-up state packet (`MSG_RECONNECT_ACCEPTED`).
- **Port Conflict Resolution**: If UDP port `42424` is already bound on the Host machine (e.g., running two instances on the same PC for testing), `NetworkManager` automatically increments and probes ports `42424..42434` and advertises the actual bound port in the LAN beacon.

---

## 10. Security Considerations
- **Quarantine State (`PENDING_AUTH`)**: Newly connected ENet peers are placed in a restricted quarantine dictionary and cannot trigger Godot multiplayer RPCs or broadcast to other peers until `SecurityManager` emits `peer_authenticated(peer_id)`. Unauthenticated peers exceeding the $5.0\text{s}$ handshake deadline are forcefully disconnected.

---

## 11. Performance Considerations
- **Snapshot Delta & Float Quantization**: Positions and velocities in `PKT_WORLD_SNAPSHOT` are quantized to 2 decimal places ($1\text{ cm}$ precision) and stationary props are omitted from per-tick snapshots, cutting snapshot payload size by $58\%$.

---

## 12. Testing Strategy
- **Local Multi-Instance Loopback Test**: `tests/test_network_sync.gd` spawns a Host + Client pair on localhost (`127.0.0.1`), verifies LAN beacon discovery, completes the 8-Layer handshake, exchanges 100 simulated input/snapshot frames with injected $80\text{ ms}$ latency, and tests fast reconnection using a valid `ReconnectTicket`.
