# Volume 2A -- Passenger & Demand Simulation

## Goal

Create a lightweight but believable passenger model that rewards
building useful networks rather than micromanagement.

## Passenger Generation

Every settlement has: - Population - Employment score - Tourism score -
Importance tier (Village, Town, City, Capital)

Each simulation tick generates potential journeys based on these
factors.

## Demand Matrix

Each origin generates journeys towards destinations weighted by: -
Population - Economic importance - Tourist attraction - Distance

If no rail route exists, journeys are assumed to use cars and generate
no railway revenue.

## Route Choice

Passengers always choose the route with the highest utility: Utility =
Journey Time + Waiting Time + Interchanges + Reliability.

## Latent Demand

Potential journeys always exist, even before a railway is built.
Building a new line unlocks previously untapped demand.

## Outputs

The simulation provides: - Passenger volumes - Train occupancy - Revenue
inputs - Happiness inputs - Capacity requirements

The same simulation feeds every other subsystem.
