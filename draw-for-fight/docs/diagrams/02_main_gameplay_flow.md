# 02. Main Gameplay Flow

## State Machine & Screen Flow

This diagram illustrates the complete player journey from booting the executable through creation, multiplayer room setup, collaborative map preparation, live 3D competition, and post-match rematch loops.

```mermaid
stateDiagram-v2
    [*] --> BootScreen: Launch Executable

    state "01. Boot & Initialization" as BootScreen {
        [*] --> LoadSettings: SettingsManager.load()
        LoadSettings --> InitCrypto: SecurityManager.init_identity()
        InitCrypto --> PreloadAssets: AudioManager & Templates
        PreloadAssets --> [*]
    }

    BootScreen --> MainMenu: Initialization Complete

    state "02. Main Menu" as MainMenu
    state "03. Character Creation" as CharCreation
    state "04. Vehicle Creation" as VehCreation
    state "05. Single / Practice Mode" as PracticeMode
    state "06. Host Room Setup" as HostRoom
    state "07. Join Room Browser" as JoinRoom
    state "08. Multiplayer Lobby" as Lobby
    state "09. Collaborative Map Editor" as MapEditor
    state "10. Active Competition Match" as ActiveMatch
    state "11. Match Results & Podium" as MatchResults

    MainMenu --> CharCreation: Create / Edit Character
    MainMenu --> VehCreation: Create / Edit Vehicle
    MainMenu --> PracticeMode: Practice / AI Sandbox
    MainMenu --> HostRoom: Host Multiplayer Game
    MainMenu --> JoinRoom: Join Multiplayer Game
    MainMenu --> [*]: Quit to Desktop

    CharCreation --> MainMenu: Save CreationData & Exit
    VehCreation --> MainMenu: Save CreationData & Exit
    PracticeMode --> MainMenu: Exit Sandbox

    HostRoom --> Lobby: Start Authoritative Server (Bind UDP + LAN Broadcast)
    JoinRoom --> Lobby: Complete 8-Layer Security Handshake

    Lobby --> MainMenu: Leave Room / Disconnect
    Lobby --> CharCreation: Quick-Edit Loadout
    Lobby --> MapEditor: All Players Ready / Host Starts Prep

    state MapEditor {
        [*] --> DrawAndPlace: 60s Prep Countdown Active
        DrawAndPlace --> ValidateArena: Timer Expired or All Locked In
        ValidateArena --> FallbackRepair: MapValidator Detects Unreachable Goal
        FallbackRepair --> SyncFinalMap: Auto-Bridge / Sanitize Applied
        ValidateArena --> SyncFinalMap: Validation Passed
        SyncFinalMap --> [*]
    }

    MapEditor --> ActiveMatch: Spawn 3D Entities & Begin 3-2-1 Countdown

    state ActiveMatch {
        [*] --> PreStartCountdown: Lock Movement Controls
        PreStartCountdown --> LiveSimulation: GO! Enable Physics & Scoring
        LiveSimulation --> OvertimeTiebreaker: Time Expired + Tied Leader Score
        LiveSimulation --> RoundComplete: Win Condition Met or Timer Zero
        OvertimeTiebreaker --> RoundComplete: Sudden Death Resolved
        RoundComplete --> [*]
    }

    ActiveMatch --> MatchResults: Broadcast Final Standings

    MatchResults --> MapEditor: Vote Rematch (Edit Map)
    MatchResults --> ActiveMatch: Vote Instant Rematch (Same Map)
    MatchResults --> Lobby: Return to Room Lobby
    MatchResults --> MainMenu: Leave Session
```
