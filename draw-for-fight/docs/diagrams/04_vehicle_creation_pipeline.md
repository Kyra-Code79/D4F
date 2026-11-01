# 04. Vehicle Creation Pipeline

## End-to-End 2D Chassis & Wheel Sketching to 3D Raycast Vehicle Flow

```mermaid
flowchart LR
    subgraph Canvas_Phase["1. Multi-Zone Vehicle Canvas"]
        Z_CHASSIS["Chassis Zone (Main Body & Rollcage Strokes)"]
        Z_WHEELS["Wheel Mount Zones (Front-Left/Right, Rear-Left/Right)"]
        Z_BUMPER["Accessory / Ramming Bumper Zone"]
        Z_SEAT["Cockpit / Character Mount Anchor"]
    end

    subgraph Process_Phase["2. Geometry Processing"]
        SIMP_C["RDP Polyline Simplification (Chassis Curve)"]
        CIRC_W["Wheel Circularity & Radius Estimator (Min/Max Radius Clamping)"]
        EXTR_C["Dual-Sided Chassis Extrusion (Width = 0.85m, Bevel = 0.08m)"]
        EXTR_W["Cylindrical Lathe / Extrusion for 4 Wheel Meshes"]
    end

    subgraph Physics_Phase["3. Jolt Vehicle Physics Assembly"]
        CHASSIS_COL["Compound Convex Collision Shapes for Chassis + Bumper"]
        COM_CALC["Center-of-Mass Lowering & Inertia Tensor Stabilization"]
        RAY_SUSP["Configure 4 Raycast Suspension Mounts (Spring Stiffness & Damping)"]
        STAT_V["Compute Engine Force, Top Speed, Grip & Ram Impulse"]
    end

    subgraph Output_Phase["4. Validation & Deployment"]
        TEST_DRIVE["3D Suspension Drop-Test in Preview Viewport"]
        SAVE_V["Serialize CreationData (type='vehicle') to JSON"]
        NET_SYNC["Compress & Replicate Strokes to Multiplayer Peers"]
    end

    Z_CHASSIS --> SIMP_C
    Z_BUMPER --> SIMP_C
    Z_WHEELS --> CIRC_W
    SIMP_C --> EXTR_C
    CIRC_W --> EXTR_W
    EXTR_C --> CHASSIS_COL
    Z_SEAT --> COM_CALC
    CHASSIS_COL --> COM_CALC
    EXTR_W --> RAY_SUSP
    COM_CALC --> STAT_V
    RAY_SUSP --> STAT_V
    STAT_V --> TEST_DRIVE
    TEST_DRIVE --> SAVE_V
    SAVE_V --> NET_SYNC
```

## Vehicle Engineering Constraints
- **Wheel Fallback Synthesis**: If a player omits wheel strokes in the Wheel Zones, the pipeline synthesizes balanced default wheels (`radius = 0.35m`) so the vehicle remains drivable.
- **Anti-Roll Stabilization**: Custom-drawn tall vehicles automatically receive a downward Center-of-Mass clamp (`y_offset <= -0.15m` relative to chassis bounds) and anti-roll bar torque within `PlayableVehicle3D` to prevent frustrating tip-overs during sharp turns.
