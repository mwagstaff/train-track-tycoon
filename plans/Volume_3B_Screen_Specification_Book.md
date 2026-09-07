# Volume 3B -- Screen Specification Book

## Purpose

This document defines the key screens, layouts and interactions for the
first playable release. Each screen includes its purpose, primary
components and acceptance criteria.

------------------------------------------------------------------------

# Screen 1 -- Home

## Purpose

Entry point into the game.

## Layout

-   Animated background showing latest railway
-   Continue Game
-   New Sandbox
-   New Career
-   Settings

## Acceptance

-   Game launches directly into last save with one tap.
-   Background railway remains animated.

------------------------------------------------------------------------

# Screen 2 -- Main Map

## Purpose

Primary gameplay screen.

## Layout

-   Full-screen MapKit
-   Floating Build button
-   Layers
-   Search
-   Pause/Speed
-   Compact HUD (Happiness, Money, Population, Passengers)

## Behaviour

-   Apple Maps style pan/zoom.
-   HUD auto-collapses while navigating.

## Acceptance

-   Map occupies \>90% of display.
-   Controls reachable with one hand.

------------------------------------------------------------------------

# Screen 3 -- Build Route

## Layout

1.  Tap Build
2.  Select origin
3.  Select destination
4.  Route preview
5.  Cost + estimated demand
6.  Confirm

## Animation

Track grows progressively across the map.

## Acceptance

Entire workflow completable within 30 seconds.

------------------------------------------------------------------------

# Screen 4 -- Station Details

## Components

-   Station level
-   Happiness
-   Population
-   Passenger numbers
-   Upgrade progress
-   Connected destinations

## Actions

-   Increase frequency
-   Upgrade
-   Build branch
-   View demand

## Acceptance

Player immediately understands why the station is busy.

------------------------------------------------------------------------

# Screen 5 -- Train Details

## Components

-   Train type
-   Route
-   Speed
-   Occupancy
-   Delay
-   Revenue
-   Next stop

## Behaviour

Selecting Follow centres camera on the moving train.

------------------------------------------------------------------------

# Screen 6 -- Line Management

## Components

-   Route map
-   Frequency slider
-   Local / Balanced / Express
-   Number of trains
-   Capacity
-   Reliability

## Advanced

Optional stop editor.

## Acceptance

Simple adjustments require no timetable knowledge.

------------------------------------------------------------------------

# Screen 7 -- Statistics

Tabs: - Happiness - Finance - Demand - Population - Network

Charts - Revenue history - Passenger growth - Network expansion -
Accessibility score

Purpose Help players identify where to expand next.

------------------------------------------------------------------------

# Screen 8 -- Layers

Toggle overlays: - Passenger demand - Accessibility - Congestion -
High-speed - Terrain - Population

Layers animate smoothly without interrupting gameplay.

------------------------------------------------------------------------

# Screen 9 -- Notifications

Examples: - Station upgraded - Route profitable - Trains overcrowded -
High-speed unlocked

Notifications appear as small glass banners and dismiss automatically.

------------------------------------------------------------------------

# Screen 10 -- Visual Standards

Glass materials for floating UI.

Rounded corners.

Large touch targets.

Minimal text.

Animations: - 200--300 ms UI transitions. - Smooth train acceleration. -
Route construction animation.

Every screen should satisfy three questions:

1.  Can the player understand it immediately?
2.  Does the map remain the visual focus?
3.  Does the railway feel alive?

If any answer is "no", simplify the design.
