# Railway Builder Game -- Product Vision & Technical Roadmap

## Vision

Create an iOS railway-building game combining the accessibility of
**Mini Metro**, the satisfaction of **Transport Tycoon**, and the
strategic progression of **Railroad Tycoon**, while using **real UK
geography** via MapKit and OSM routing.

The player builds a living railway on a real map, watches trains move,
grows towns, improves accessibility and passenger happiness, and
gradually develops a world-class network.

------------------------------------------------------------------------

# Core Design Principles

-   Real geography using MapKit.
-   Real railway routing using existing TrainTrack UK routing engine.
-   Simple controls, deep simulation.
-   Beautiful to watch.
-   No timetable micromanagement.
-   Strategic rather than operational gameplay.

------------------------------------------------------------------------

# Core Gameplay Pillars

## 1. Build

Player selects two towns/stations.

Game automatically computes the railway route using the existing routing
engine.

Player confirms construction.

No manual track laying.

## 2. Grow

Stations upgrade automatically.

-   Halt
-   Local Station
-   Town Station
-   Major Station
-   Interchange
-   Terminus

Growth depends on passenger usage.

## 3. Operate

Player chooses:

-   Frequency
-   Stopping / Balanced / Express
-   Train type
-   Upgrades

Simulation handles everything else.

------------------------------------------------------------------------

# Game Modes

## Zen Mode

Unlimited money.

Player still sees:

-   Construction cost
-   Revenue
-   Operating costs
-   Network value
-   Commercial viability

Primary objective:

**Maximise Passenger Happiness.**

## Career Mode

Budget limited.

Loans available.

Expansion must be financially sustainable.

------------------------------------------------------------------------

# Passenger Happiness

This is the primary score.

Rather than simply measuring delays, happiness measures
**Accessibility**.

Factors:

  Metric                       Weight
  ---------------------------- --------
  Reachable destinations       30%
  Importance of destinations   20%
  Journey time                 20%
  Frequency                    15%
  Reliability                  10%
  Crowding                     5%

The game should also show WHY happiness changed.

Example:

-   Excellent London access
-   Brighton journeys are slow
-   Peak trains overcrowded
-   Poor east-west connectivity

Use diminishing returns for frequency so excessive train density is not
optimal.

------------------------------------------------------------------------

# Economy

Income

-   Ticket revenue
-   Passenger growth
-   Tourism
-   Freight (future)

Costs

-   Track
-   Bridges
-   Tunnels
-   Stations
-   Trains
-   Maintenance
-   Staff
-   Electricity

Passenger simulation drives both revenue and happiness.

------------------------------------------------------------------------

# Service Patterns

Player selects:

-   Local
-   Balanced
-   Express

The game automatically chooses stopping patterns.

Advanced mode allows station-by-station editing.

------------------------------------------------------------------------

# High Speed Rail

Separate infrastructure class.

Advantages

-   Massive journey time reductions
-   Huge accessibility improvements
-   Premium revenue
-   Prestige

Disadvantages

-   Extremely expensive
-   Dedicated infrastructure
-   Special stations

------------------------------------------------------------------------

# Visual Style

Three layers:

1.  MapKit basemap
2.  Custom railway overlay
3.  Animated stations and trains

Train assets:

-   Generic top-down sprites
-   Slightly oversized
-   Rotate continuously with route bearing

Station assets:

-   Vector artwork
-   Upgrade visually as stations grow

Visual progression:

UK View → dots

Regional → small train icons

Town → detailed train sprites

Close → animated trains with shadows

------------------------------------------------------------------------

# Suggested Technical Architecture

MapKit

↓

Track Overlay Renderer

↓

Station Layer

↓

Animated Train Layer

↓

Simulation Engine

↓

Economy & Happiness

------------------------------------------------------------------------

# Initial Technology Stack

-   SwiftUI
-   MapKit
-   Existing OSM routing engine
-   SpriteKit or Core Animation for trains
-   SwiftData (later)
-   CloudKit (future saves)

------------------------------------------------------------------------

# Milestones

## Milestone 0 --- Vision & Technical Spike (1 week)

Goal:

Validate the core rendering concept.

Deliverables

-   MapKit UK map
-   Existing OSM routing
-   Custom coloured route overlay
-   One animated train sprite moving along a route
-   Zooming and rotation working smoothly

Success criteria

"It already feels satisfying to watch."

------------------------------------------------------------------------

## Milestone 1 --- Proof of Concept

Goal:

Prove the game is fun before building simulation.

Deliverables

-   Build route between towns
-   Route construction animation
-   Generic stations
-   One train per route
-   Camera follows train
-   Simple HUD
-   Build costs displayed

No economy.

No passengers.

No happiness.

No saving.

Success criteria

Building and watching trains is enjoyable.

------------------------------------------------------------------------

## Milestone 2 --- Living Network

Add

-   Passenger generation
-   Station upgrades
-   Multiple trains
-   Frequency control
-   Animated occupancy
-   Route colours

------------------------------------------------------------------------

## Milestone 3 --- Passenger Happiness

Implement accessibility algorithm.

Town-by-town happiness.

Heatmaps.

Destination scoring.

Performance dashboard.

------------------------------------------------------------------------

## Milestone 4 --- Economy

Implement

-   Revenue
-   Maintenance
-   Rolling stock
-   Construction
-   Loans
-   Profit/loss

Zen mode introduced.

------------------------------------------------------------------------

## Milestone 5 --- Service Patterns

Implement

-   Local
-   Balanced
-   Express
-   Passing loops
-   Overtaking
-   Congestion

Watching expresses overtake stopping services becomes a key visual
reward.

------------------------------------------------------------------------

## Milestone 6 --- High Speed

Introduce

-   Dedicated HSR
-   Premium stations
-   200+ mph trains
-   Accessibility boost
-   Huge construction costs

------------------------------------------------------------------------

## Milestone 7 --- Polish

-   Dynamic weather
-   Day/night cycle
-   Better train artwork
-   Population growth
-   Sound
-   Achievements
-   Steam-style statistics
-   Replay mode

------------------------------------------------------------------------

# Future Ideas

-   Freight
-   Multiplayer shared worlds
-   Steam Workshop-style sharing
-   Real-world scenarios
-   Historic railway eras
-   Electrification
-   Diesel retirement
-   AI competitors
-   Modding

------------------------------------------------------------------------

# Definition of Success

A successful game should make the player repeatedly think:

"I'll just build one more line."

The emphasis is on creating a beautiful, living railway rather than
simulating every operational detail. The player's decisions should focus
on:

1.  Where should the railway go?
2.  Where should trains stop?
3.  How frequently should they run?
4.  Where should investment be made?

Everything else should be automated by the simulation.
