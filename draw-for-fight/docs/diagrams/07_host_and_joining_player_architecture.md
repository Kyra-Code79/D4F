# 07. Host and Joining Player Architecture

## Self-Hosted Listen-Server (Host-as-Player) vs. Joining Client Topology

```mermaid
flowchart TD
    subgraph Host_Machine["Host Player Machine (Peer ID = 1 | Authoritative Server + Local Client)"]
        direction TB
        subgraph Host_Client_Side["Local Client Presentation & Input"]
            H_Input["Local Input Polling (Keyboard/Mouse)"]
            H_UI["HUD, Lobby & Collaborative Editor UI"]
            H_Render["GL Compatibility 3D Renderer & Audio Listener"]
        end

        subgraph Host_Server_Side["Authoritative Server Engine"]
            H_Sec["SecurityManager (Host Authority: DTLS, Challenge Gen, HKDF, EtM, RBAC)"]
            H_Net["NetworkManager (ENet Server Socket + LAN UDP Broadcaster :42425)"]
            H_Match["MatchManager (Room State, Timers, Authoritative Scorekeeper)"]
            H_Phys["Authoritative Jolt Physics 3D World (60 Hz Fixed Tick)"]
            H_AI["AIAssistantManager (Server Bot Controllers)"]
        end

        H_Input -->|"Zero-Latency Local Command"| H_Phys
        H_Phys -->|"Direct Node Transform Read"| H_Render
        H_Match --> H_UI
        H_AI --> H_Phys
        H_Phys -->|"Generate 20 Hz State Snapshots"| H_Net
        H_Net <--> H_Sec
    end

    subgraph Network_Fabric["Transport Medium (LAN / Direct UDP / Optional Relay)"]
        UDP_Disc["UDP LAN Broadcast (:42425 Room Beacon)"]
        ENet_Pipe["Encrypted ENet Channels (0: Control/Auth, 1: Map/Creation Sync, 2: Unreliable Snapshots)"]
        Relay_Srv["Optional RelayConnector (NAT Punchthrough / Encrypted Packet Forwarder)"]
    end

    subgraph Client_Machine["Joining Player Machine (Peer ID = 2..8 | Remote Client)"]
        direction TB
        C_Input["Local Input Capture (Seq#, Timestamp, MoveVector, ActionFlags)"]
        C_Pred["Client-Side Prediction & Server Reconciliation Buffer"]
        C_Interp["Snapshot Interpolation Buffer (100ms Render Delay for Remote Entities)"]
        C_Sec["SecurityManager (Client Peer: Handshake Responder, EtM Cipher)"]
        C_Net["NetworkManager (ENet Client Socket + LAN Listener)"]
        C_Render["GL Compatibility 3D Renderer, Local Proxy Physics & UI"]

        C_Input -->|"1. Send Input Command (60 Hz)"| C_Net
        C_Input -->|"2. Immediate Local Prediction"| C_Pred
        C_Net <--> C_Sec
        C_Net -->|"3. Receive Authoritative Snapshot"| C_Pred
        C_Net -->|"4. Feed Remote Entity States"| C_Interp
        C_Pred --> C_Render
        C_Interp --> C_Render
    end

    H_Net -.->|"Periodic Beacon (Every 1.5s)"| UDP_Disc
    UDP_Disc -.->|"Auto-Populate Room List"| C_Net
    H_Sec <==>|"Direct UDP or via Relay"| ENet_Pipe
    ENet_Pipe <==> Relay_Srv
    Relay_Srv <==> C_Sec
    ENet_Pipe <==> C_Sec
```

## Topology Highlights
- **No Dedicated Server Required**: Any player clicking **Host Room** starts an embedded authoritative server (`Peer ID = 1`) while simultaneously playing locally in the same process.
- **Anti-Host-Advantage Fairness**: Although the Host has zero network RTT, local host input is queued into the exact same 60 Hz physics tick buffer and subject to the same `AttributeCalculator` movement caps and cooldown timers as remote clients.
- **Channel Segregation**:
  - `Channel 0` (Reliable Ordered): 8-Layer Security Handshake, Lobby state transitions, Match lifecycle events.
  - `Channel 1` (Reliable Ordered, Chunked): Custom Character/Vehicle `CreationData` and Collaborative Map deltas.
  - `Channel 2` (Unreliable Sequenced): High-frequency 60 Hz client input frames and 20 Hz server physics snapshots.
