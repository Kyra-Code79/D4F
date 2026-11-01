# 08. Multiplayer Connection Sequence

## Room Discovery, Transport Setup, Handshake, and Lobby Synchronization

```mermaid
sequenceDiagram
    autonumber
    actor Host as Host Player (Server Peer 1)
    participant Disc as LAN UDP Discovery (:42425)
    participant Relay as Optional RelayConnector
    actor Client as Joining Player (Client Peer N)

    Note over Host,Disc: 1. Host Initializes Authoritative Room
    Host->>Host: NetworkManager.host_room(Port=42424, MaxPlayers=8, RoomCode, PasswordHash)
    Host->>Disc: Broadcast UDP Beacon every 1.5s (RoomName, Mode, Players=1/8, Port, RequiresPass)

    alt LAN / Direct IP Discovery
        Disc-->>Client: Receive Beacon on Port 42425 -> Populate Join Room UI List
        Client->>Host: ENet Connect to Host_IP:42424
    else Relay Code Connection (NAT Traversal Fallback)
        Host->>Relay: Register Room Code & Allocate Relay Tunnel
        Client->>Relay: Request Tunnel for Room Code
        Relay-->>Client: Bind Virtual Endpoint -> Forward ENet UDP Datagrams
    end

    Host-->>Client: ENet Connection Established (Assign Temporary Peer_ID, State=PENDING_AUTH)
    Note over Host,Client: Peer is quarantined in PENDING_AUTH (5.0s Timeout); cannot send gameplay RPCs

    Host->>Client: Execute 8-Layer Security Handshake (Channel 0)
    Client->>Host: Complete Handshake & Session Key Derivation
    Host->>Host: Promote Peer State -> AUTHENTICATED (Assign RBAC Role = PLAYER, Issue ReconnectToken)

    Host->>Client: Send MSG_LOBBY_WELCOME (ReconnectToken, RoomConfig, CurrentPlayerRoster, SelectedMode)
    Client->>Host: Send MSG_UPLOAD_CREATION (Compressed Character/Vehicle CreationData JSON)
    Host->>Host: D4FSerializer.sanitize() + AttributeCalculator.verify_bounds()
    Host->>Client: Broadcast EVT_PLAYER_JOINED_AND_READY (Peer_ID, ProfileName, ValidatedCreationSummary)
    Note over Host,Client: Both Host and Client Render 3D Preview of All Connected Players in Lobby
```
