# Volume 3 -- UI/UX & Art Direction

## 1. Purpose

This document defines the visual identity, interaction model and user
experience for the Railway Builder game. The objective is to create a
premium, modern iOS experience that is immediately understandable while
conveying the feeling of a living railway.

------------------------------------------------------------------------

# 2. Design Philosophy

The UI should be:

-   Calm rather than cluttered
-   Beautiful rather than hyper-realistic
-   Information rich but progressive
-   Optimised for touch
-   Focused on the map as the hero

The railway itself is the primary visual element; UI should support
rather than dominate it.

------------------------------------------------------------------------

# 3. Visual Style

Inspirations:

-   Transport Tycoon Deluxe (living world)
-   Mini Metro (clarity)
-   Apple Maps (fluid interaction)
-   Modern iOS glass materials

Palette:

-   Natural terrain colours
-   Bright railway line colours
-   Soft glass panels
-   Subtle shadows
-   Smooth animations (60--120 fps)

------------------------------------------------------------------------

# 4. Camera & Navigation

Zoom levels:

### National

-   Entire UK
-   Major cities
-   Trains shown as moving dots

### Regional

-   Individual corridors
-   Station names
-   Small train sprites

### Local

-   Visible track geometry
-   Animated train sprites
-   Detailed station markers

### Station

-   Platforms and trains visible
-   Service activity
-   Optional passenger animations (future)

Pinch, pan and double-tap should feel identical to Apple Maps.

------------------------------------------------------------------------

# 5. Map Layers

Bottom to top:

1.  MapKit basemap
2.  Railway overlay
3.  High-speed overlay
4.  Station markers
5.  Train sprites
6.  Weather/time effects
7.  HUD

Users can optionally toggle traffic layers such as demand heatmaps and
accessibility.

------------------------------------------------------------------------

# 6. Home Screen

Primary actions:

-   Continue Game
-   New Sandbox
-   New Career
-   Scenarios (future)
-   Settings

Background shows the player's latest railway operating in real time.

------------------------------------------------------------------------

# 7. Main Game Screen

The map occupies almost the entire display.

Floating controls:

-   Build
-   Inspect
-   Layers
-   Statistics
-   Pause / Speed
-   Search

A compact glass HUD displays:

-   Happiness
-   Money
-   Population
-   Passengers today

------------------------------------------------------------------------

# 8. Construction UX

Tap "Build".

Tap origin.

Tap destination.

Preview route.

Display:

-   Cost
-   Journey length
-   Estimated demand
-   Construction time (Career)

Press Build.

Animated construction traces along the route.

------------------------------------------------------------------------

# 9. Train Interaction

Tap any train to open a card.

Suggested fields:

-   Service name
-   Current speed
-   Occupancy
-   Next stop
-   Delay
-   Revenue today

Selecting a train follows it with the camera.

------------------------------------------------------------------------

# 10. Station Interaction

Tap station.

Display:

-   Population
-   Happiness
-   Passenger numbers
-   Connected destinations
-   Station level
-   Upgrade progress

Suggested actions:

-   Increase frequency
-   Upgrade station
-   Build branch
-   View demand

------------------------------------------------------------------------

# 11. Service Management

Each line exposes simple controls:

-   Frequency slider
-   Local
-   Balanced
-   Express

Advanced users may edit calling points, but this remains optional.

------------------------------------------------------------------------

# 12. Visual Progression

The world should visibly evolve.

Small halt:

-   Single platform
-   Tiny marker

Town station:

-   Larger building
-   More platforms

Interchange:

-   Distinctive icon
-   Busy train movements

High-speed station:

-   Unique architecture
-   Premium appearance

Players should recognise growth without opening information panels.

------------------------------------------------------------------------

# 13. Animation Principles

Animations should be:

-   Smooth
-   Purposeful
-   Short
-   Physically believable

Examples:

-   Trains accelerate and brake gently.
-   Stations pulse subtly when busy.
-   New track grows across the map during construction.
-   High-speed trains visibly move faster than local services.

------------------------------------------------------------------------

# 14. Sound

Minimalist soundscape.

Examples:

-   Soft construction sounds
-   Passing train ambience
-   Station announcements (optional)
-   Gentle UI clicks

Avoid repetitive effects.

------------------------------------------------------------------------

# 15. Accessibility

Support:

-   Dynamic Type where appropriate
-   VoiceOver
-   Colour-blind friendly overlays
-   High contrast mode
-   Reduced motion

Gameplay must remain readable without relying solely on colour.

------------------------------------------------------------------------

# 16. Art Asset Strategy

Train assets:

-   Top-down sprites
-   Generic EMU
-   Generic DMU
-   Freight
-   High-speed

Station assets:

-   Vector artwork
-   Six upgrade levels

All artwork should be data-driven so assets can evolve without changing
game logic.

------------------------------------------------------------------------

# 17. Future Visual Features

-   Day/night cycle
-   Dynamic weather
-   Seasonal scenery
-   Autumn colours
-   Snow
-   Fog
-   Rain reflections
-   Animated rivers and coastlines

------------------------------------------------------------------------

# 18. UX Success Criteria

The interface succeeds if a new player can:

-   Build a railway within one minute.
-   Understand the HUD without a tutorial.
-   Enjoy watching trains without interacting.
-   Instinctively discover new features.
-   Feel proud of the railway they have created.

Every screen should reinforce the game's central promise:

**Build a beautiful railway. Watch it come alive.**
