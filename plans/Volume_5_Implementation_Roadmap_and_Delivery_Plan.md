# Volume 5 -- Implementation Roadmap & Delivery Plan

## 1. Purpose

This document defines the implementation strategy for Railway Builder,
breaking development into manageable milestones with clear acceptance
criteria. Every milestone should leave the project in a playable state.

------------------------------------------------------------------------

# 2. Development Philosophy

Principles:

-   Deliver playable software early.
-   Optimise for visible progress.
-   Build reusable systems.
-   Keep gameplay ahead of feature count.
-   Validate assumptions before adding complexity.

------------------------------------------------------------------------

# 3. Milestone 0 -- Technical Spike (1--2 weeks)

## Objective

Prove that the core technology stack is viable.

## Deliverables

-   SwiftUI application shell
-   MapKit integration
-   Existing OSM routing engine integrated
-   Railway overlay renderer
-   Single animated train sprite
-   Smooth pan/zoom
-   Basic performance instrumentation

## Success Criteria

-   60 FPS on target hardware.
-   Train follows route accurately.
-   Camera interaction feels like Apple Maps.

------------------------------------------------------------------------

# 4. Milestone 1 -- Playable Proof of Concept

## Objective

Answer the question:

**"Is building and watching trains fun?"**

## Deliverables

-   Build route between settlements
-   Route preview
-   Construction animation
-   Generic station markers
-   Multiple routes
-   Train follows completed routes
-   Save/load

## Out of Scope

-   Economy
-   Passengers
-   Happiness
-   AI

## Exit Criteria

Players naturally want to continue expanding their railway.

------------------------------------------------------------------------

# 5. Milestone 2 -- Living Network

## Features

-   Passenger demand generation
-   Train occupancy
-   Station usage
-   Multiple simultaneous trains
-   Frequency controls
-   Station upgrades
-   Animated station activity

## Acceptance

The network begins to feel alive without requiring player
micromanagement.

------------------------------------------------------------------------

# 6. Milestone 3 -- Accessibility & Happiness

Implement:

-   Settlement accessibility
-   Global happiness
-   Local happiness
-   Heatmaps
-   Player feedback
-   Network statistics

Acceptance:

Players clearly understand why their network succeeds or fails.

------------------------------------------------------------------------

# 7. Milestone 4 -- Economy

Implement:

Revenue - Passenger fares - Network value

Costs - Construction - Rolling stock - Maintenance - Energy

Career Mode - Loans - Bankruptcy - Expansion decisions

Zen Mode - Unlimited budget - Financial statistics only

Acceptance:

Money influences decisions without dominating gameplay.

------------------------------------------------------------------------

# 8. Milestone 5 -- Operations

Features

-   Local services
-   Express services
-   Balanced services
-   Congestion
-   Passing loops
-   Additional tracks
-   Line management

Acceptance

Watching express trains overtake slower services becomes a key gameplay
reward.

------------------------------------------------------------------------

# 9. Milestone 6 -- High-Speed Rail

Introduce

-   Dedicated high-speed track
-   Premium stations
-   Faster rolling stock
-   Major construction costs
-   Accessibility boost
-   Prestige bonuses

Acceptance

Building a high-speed corridor feels like a transformational
achievement.

------------------------------------------------------------------------

# 10. Milestone 7 -- Polish

Visual improvements

-   Day/night cycle
-   Weather
-   Sound
-   Particle effects
-   Better sprites
-   Construction effects

Gameplay improvements

-   Achievements
-   Scenarios
-   Difficulty balancing
-   Tutorial
-   Accessibility review

Acceptance

Game is suitable for public beta.

------------------------------------------------------------------------

# 11. Quality Assurance

Testing strategy

-   Unit tests for simulation
-   Snapshot tests for UI
-   Performance benchmarks
-   Save/load compatibility
-   Long-running simulation testing

Regression tests should accompany every gameplay feature.

------------------------------------------------------------------------

# 12. Risk Register

  -----------------------------------------------------------------------
  Risk                    Mitigation
  ----------------------- -----------------------------------------------
  Rendering performance   Level-of-detail system, animate only visible
                          trains

  Simulation complexity   Separate simulation from rendering

  Scope creep             Deliver milestones independently

  Asset production        Use generic sprites first

  Gameplay depth          Validate each mechanic with playtesting
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 13. Success Metrics

Technical

-   Stable 60 FPS
-   \<2 second load time
-   No simulation drift
-   Reliable autosaves

Gameplay

-   Players build multiple lines in first session
-   Happiness system is understood
-   Watching trains remains enjoyable
-   Expansion decisions feel meaningful

------------------------------------------------------------------------

# 14. Backlog (Post-Launch)

-   Freight operations
-   Steam era scenarios
-   Historical timelines
-   Electrification
-   Multiplayer
-   Shared maps
-   Steam Workshop-style sharing
-   Seasonal events
-   AI railway companies
-   Mac version
-   iPad optimisation

------------------------------------------------------------------------

# 15. Release Strategy

Phase 1 - Internal prototype

Phase 2 - Friends & family testing

Phase 3 - Closed TestFlight

Phase 4 - Open TestFlight

Phase 5 - App Store launch

Gather player feedback after each phase and rebalance accordingly.

------------------------------------------------------------------------

# 16. Definition of Done

Each milestone is complete only when:

-   Acceptance criteria are met.
-   Performance targets are achieved.
-   Save/load works.
-   No known critical defects remain.
-   Documentation is updated.
-   The game is enjoyable in its current state.

------------------------------------------------------------------------

# 17. Final Vision

The completed game should offer a uniquely relaxing experience where
players build a railway across real UK geography, watch it evolve into a
thriving transport network, and continually discover meaningful
opportunities to improve accessibility, passenger happiness and
prestige.

The ultimate success metric is simple:

**Players finish a session already planning the next line they want to
build.**
