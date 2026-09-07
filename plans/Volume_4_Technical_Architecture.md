# Volume 4 -- Technical Architecture

## 1. Purpose

This document defines the high-level technical architecture for Railway
Builder. The goal is to create a scalable, data-driven simulation
capable of rendering thousands of kilometres of railway while
maintaining a smooth native iOS experience.

------------------------------------------------------------------------

# 2. Core Architecture

The game is divided into independent systems:

    SwiftUI
        ↓
    Game Coordinator
        ↓
    Map Renderer
    Simulation Engine
    UI Layer
    Persistence

Each subsystem communicates through well-defined models rather than
directly depending on one another.

------------------------------------------------------------------------

# 3. Rendering Pipeline

    MapKit Basemap
            ↓
    Railway Overlay Renderer
            ↓
    Station Layer
            ↓
    Animated Train Layer
            ↓
    Effects (weather, time)
            ↓
    HUD

Rendering must remain independent from simulation.

------------------------------------------------------------------------

# 4. Map & Routing

## Map

-   Apple MapKit
-   Vector maps
-   Native gestures
-   Dynamic zoom

## Routing

Reuse the existing TrainTrack UK routing engine.

Responsibilities:

-   Route construction
-   Distance calculation
-   Journey time estimation
-   Geometry generation
-   High-speed routing (future)

The routing engine should expose clean APIs and remain reusable.

------------------------------------------------------------------------

# 5. Simulation Engine

Simulation runs on discrete ticks.

Suggested cadence:

-   Economy: every 30--60 seconds
-   Passenger generation: every minute
-   Train movement: every frame (interpolated)
-   Population growth: daily
-   Station upgrades: periodic

Separate logical simulation from rendering interpolation.

------------------------------------------------------------------------

# 6. Core Domain Models

Primary entities:

-   Settlement
-   Station
-   TrackSegment
-   RailwayLine
-   Train
-   PassengerDemand
-   Journey
-   Player
-   Network

Relationships should be ID-based to simplify persistence.

------------------------------------------------------------------------

# 7. Rendering Strategy

Use lightweight sprites.

Trains: - Generic sprite - Rotation from track bearing - Scale varies
with zoom

Stations: - Vector artwork - Upgrade by level

Tracks: - Custom MapKit overlays - Optional sleepers at close zoom -
Colour-coded services

------------------------------------------------------------------------

# 8. Persistence

Suggested technologies:

-   SwiftData
-   Codable save files
-   Versioned schema

Persist:

-   Network
-   Economy
-   Happiness
-   Population
-   Research
-   Camera state

Autosave periodically.

------------------------------------------------------------------------

# 9. Performance Targets

Target devices:

-   iPhone 15+
-   iPad
-   Apple Silicon Macs (future)

Performance goals:

-   60 FPS minimum
-   120 FPS where supported
-   \<2 second load time
-   Background simulation off main thread
-   Incremental redraws only

Only visible trains should be animated in detail.

------------------------------------------------------------------------

# 10. Extensibility

Future systems should plug into the architecture without major redesign.

Examples:

-   Multiplayer
-   Steam-style scenarios
-   Weather
-   Freight
-   AI operators
-   Modding
-   Cloud saves
-   Leaderboards

Data-driven configuration should be preferred over hard-coded rules.

------------------------------------------------------------------------

# 11. Milestone Architecture

## Milestone 0

-   MapKit
-   Routing integration
-   One animated train

## Milestone 1

-   Route building
-   Generic stations
-   Save/load

## Milestone 2

-   Passenger simulation
-   Multiple trains

## Milestone 3

-   Economy
-   Happiness

## Milestone 4

-   Express operations
-   Congestion
-   High-speed rail

Each milestone should leave the codebase in a releasable state.

------------------------------------------------------------------------

# 12. Engineering Principles

-   Composition over inheritance.
-   Data-driven gameplay.
-   Deterministic simulation.
-   Testable business logic.
-   Thin SwiftUI views.
-   Independent rendering and simulation.
-   Prefer reusable packages for routing, simulation and UI.

The architecture should prioritise maintainability, allowing new
gameplay systems to be added without restructuring existing code.
