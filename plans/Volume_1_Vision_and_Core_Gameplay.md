# Volume 1 -- Vision & Core Gameplay

## 1. Purpose

This document defines the overall vision, player experience and core
gameplay for the Railway Builder game. It intentionally avoids low-level
technical implementation and instead describes *what* the game should
feel like and *why* players will keep coming back.

The guiding ambition is to build a relaxing yet rewarding railway
sandbox that combines real-world geography with approachable management
gameplay.

------------------------------------------------------------------------

# 2. Vision Statement

**Build, grow and watch a living railway network on a real map of the
United Kingdom.**

Unlike traditional railway simulators, players do not lay individual
rails or manage detailed timetables. They make strategic
decisions---where to build, which towns to connect, how frequently
trains should run, and when to invest in faster infrastructure---while
the simulation handles operational complexity.

The game should evoke the joy of creating a model railway brought to
life on real geography.

------------------------------------------------------------------------

# 3. Design Principles

Every feature should satisfy these principles:

-   Real geography, simplified gameplay.
-   Easy to learn, difficult to optimise.
-   Watching the railway should be as enjoyable as building it.
-   Every new line should feel meaningful.
-   Strategic choices over administrative micromanagement.
-   A clean, premium iOS experience.

If a feature adds complexity without improving these goals, it should be
reconsidered.

------------------------------------------------------------------------

# 4. Target Audience

Primary audience:

-   Fans of Mini Metro, Transport Tycoon and Railroad Tycoon.
-   Railway enthusiasts.
-   Players who enjoy creative sandbox games.
-   Casual players looking for a relaxing experience.

The game should be playable in short sessions but equally enjoyable over
many hours.

------------------------------------------------------------------------

# 5. Core Gameplay Loop

1.  Build a new railway connection.
2.  Watch trains begin operating.
3.  More destinations become accessible.
4.  Passenger happiness increases.
5.  Revenue grows (Career Mode).
6.  Expand and improve the network.
7.  Repeat.

The loop should always provide a visible reward for expansion.

------------------------------------------------------------------------

# 6. Game Modes

## Zen Mode

-   Unlimited budget.
-   Full statistics still displayed.
-   Happiness remains the primary objective.
-   No bankruptcy.
-   Encourages creativity and experimentation.

## Career Mode

-   Limited starting budget.
-   Construction and operating costs matter.
-   Expansion requires profitable decisions.
-   Loans and financial management become important.

------------------------------------------------------------------------

# 7. Player Decisions

Players should primarily answer four questions:

1.  Where should the railway go?
2.  Where should trains stop?
3.  How many trains should run?
4.  Where should investment be made?

Everything else should be automated.

------------------------------------------------------------------------

# 8. What the Player Builds

Players create:

-   Railway lines
-   Stations
-   Interchanges
-   Passing loops (later)
-   High-speed corridors (later)

Stations grow automatically through increased usage.

------------------------------------------------------------------------

# 9. Success Metrics

The game measures success using:

## Passenger Happiness

Represents accessibility, journey quality and network usefulness.

## Network Size

Total track, stations and destinations served.

## Financial Health

Relevant in Career Mode.

## Prestige

Awarded for ambitious projects such as high-speed rail and major
interchanges.

------------------------------------------------------------------------

# 10. Proof of Concept (Milestone 1)

The initial Proof of Concept should validate one question:

**"Is building and watching trains on a real map genuinely fun?"**

Deliverables:

-   MapKit UK map.
-   Existing OSM routing integration.
-   Route construction between towns.
-   Generic station markers.
-   Animated train sprite travelling along the route.
-   Camera zoom and pan.
-   Simple build HUD.
-   Basic construction cost display.

No passenger simulation, economy, saving or AI is required at this
stage.

Success criteria:

-   Route creation feels intuitive.
-   Train movement is smooth and satisfying.
-   Players naturally want to build another line.

------------------------------------------------------------------------

# 11. Long-Term Vision

As the project evolves, the railway should become a living world. Towns
grow, stations expand, express trains overtake stopping services, and
high-speed rail reshapes the country's accessibility.

The game should encourage players to stand back, watch their railway
operate, and feel proud of what they have built.

A successful player should regularly think:

> "I'll just build one more line."

That feeling is the core objective of the project.
