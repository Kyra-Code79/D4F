# 01. Overall Game Architecture

## Architectural Overview

Draw for Fight (D4F) employs a layered, modular architecture built on Godot Engine 4.x (`GL Compatibility` renderer + `Jolt Physics` 3D engine). Global state, networking, security, and match orchestration are managed by seven Autoload singletons that bridge the Presentation UI Layer, the Creative & Conversion Pipeline, the 3D Gameplay & Physics Engine, and the Authoritative Multiplayer & Security Transport Layer.

```mermaid
flowchart TD
    subgraph UI_Layer["Presentation & UI Layer (res://scenes/ui/)"]
        S1["01. Splash / Boot Screen"]
        S2["02. Main Menu"]
        S3["03. Character Creation Screen"]
        S4["04. Vehicle Creation Screen"]
        S5["05. Single / Practice Mode"]
        S6["06. Host Room Screen"]
        S7["07. Join Room Screen"]
        S8["08. Multiplayer Lobby"]
        S9["09. Collaborative Map Editor"]
        S10["10. Active Match HUD"]
        S11["11. Match Results & Rematch"]
    end

    subgraph Autoloads["Core Autoload Singletons (res://scripts/autoload/)"]
        GM["GameManager (State & Scene Router)"]
        SM["SettingsManager (Config & Graphics/Input)"]
        SecM["SecurityManager (8-Layer Crypto & RBAC)"]
        NM["NetworkManager (ENet Host/Client, Discovery, Relay)"]
        MM["MatchManager (Lobby, Map Prep, Competition Lifecycle)"]
        AM["AudioManager (SFX Pool & BGM Crossfader)"]
        AIM["AIAssistantManager (Draw Suggestions & Bot AI)"]
    end

    subgraph Creation_Pipeline["2D-to-3D Creation Pipeline (res://scripts/creation/)"]
        Canvas["DrawingCanvas2D (Strokes, Brushes, Undo/Redo)"]
        RDP["PolylineSimplifier (Ramer-Douglas-Peucker)"]
        Gen3D["MeshExtruder3D (SurfaceTool Ribbon & Bevel)"]
        ColGen["CollisionBuilder3D (Convex Hull Decomposition)"]
        StatCalc["AttributeCalculator (Mass, Speed, Stability, Knockback)"]
    end

    subgraph Gameplay_Layer["3D Gameplay & Jolt Physics Layer (res://scripts/gameplay/)"]
        Char3D["PlayableCharacter3D (CharacterBody3D / RigidBody3D)"]
        Veh3D["PlayableVehicle3D (VehicleBody3D + Raycast Suspension)"]
        Map3D["CollaborativeArena3D (Terrain Extrusion & Placed Props)"]
        MapVal["MapValidator (A* Reachability & Anti-Griefing)"]
        Modes["CompetitionModeBase (Race, Survival, Battle, Custom)"]
    end

    subgraph Persistence_Net["Persistence & Transport I/O"]
        Ser["D4FSerializer (JSON Schema + NaN/Inf Sanitizer)"]
        Disk["Local Storage (user://creations/, user://maps/, user://settings.cfg)"]
        ENet["ENetMultiplayerPeer + DTLS / AES-256-CBC EtM Packet Pipe"]
    end

    UI_Layer --> GM
    UI_Layer --> SM
    UI_Layer --> AM

    S3 --> Canvas
    S4 --> Canvas
    Canvas --> RDP
    RDP --> Gen3D
    RDP --> ColGen
    Gen3D --> StatCalc
    ColGen --> StatCalc
    StatCalc --> Ser
    Ser --> Disk

    S6 --> NM
    S7 --> NM
    S8 --> MM
    S9 --> Map3D
    S9 --> MapVal
    S10 --> Modes
    S11 --> MM

    GM --> MM
    MM --> NM
    NM --> SecM
    SecM --> ENet

    MM --> Modes
    Modes --> Char3D
    Modes --> Veh3D
    Modes --> Map3D
    AIM --> Canvas
    AIM --> Char3D
    AIM --> Veh3D
```

## Key Architectural Invariants
- **Strict Separation of Concerns**: UI screens never directly mutate network sockets or physics servers; all transitions pass through `GameManager`, `MatchManager`, and `NetworkManager`.
- **Deterministic Validation**: Every custom character, vehicle, and map modification is validated through `AttributeCalculator` and `MapValidator` on both client preview and authoritative host before spawning in 3D space.
- **Zero-Trust Network Boundary**: All packets traversing `ENetMultiplayerPeer` are authenticated, rate-limited, and verified by `SecurityManager` before reaching gameplay nodes.
