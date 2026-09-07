# TrainTrack Tycoon

TrainTrack Tycoon is a portrait-first iPhone railway-building game prototype. The proof of concept tests one idea: whether choosing real stations, constructing a line over real Great Britain railway geometry, and watching trains run is satisfying.

## Milestone roadmap

- **M0 — Vision & technical spike:** validate MapKit, OSM railway routing, overlays, and moving trains.
- **M1 — Proof of concept:** build a routed line and watch a train run.
- **M2 — Living network:** passengers, station evolution, multiple trains, and frequency control.
- **M3 — Passenger happiness:** accessibility, settlement scores, heatmaps, and performance views.
- **M4 — Economy:** revenue, costs, construction, loans, Career mode, and Zen mode.
- **M5 — Service patterns:** Local, Balanced, Express, passing loops, overtaking, and congestion.
- **M6 — High speed:** dedicated infrastructure, premium stations, fast trains, and prestige.
- **M7 — Polish:** world effects, day/night, sound, onboarding, achievements, and statistics.
- **M8 — Public-beta hardening:** persistence recovery, simulation soaks, accessibility, and UI regression coverage.
- **M9 — Population and station growth:** synthetic settlement growth tied to railway accessibility.
- **M10 — Connecting journeys:** one-change passenger markets through a shared station.
- **M11 — Real rolling stock and capacity:** purchased 2–12-car formations with real seat, cost, and visual effects.
- **M12 — Station capacity and hub bottlenecks:** platform throughput now constrains effective service frequency.
- **M13 — Network foundations and scalable lines:** separate corridors and services, support up to 12 services, and generalise one-change demand and hub capacity.
- **M14 — Real intermediate stations:** discover, build and operate real ordered calls along retained corridors.
- **M15 — Through services:** destructively merge adjacent conventional services into a linear
  through service spanning any number of retained corridors without rebuilding purchased track.
- **M16 — Custom local and express services:** choose independent terminals and Local or Express
  calling patterns for each active train over the service's existing infrastructure.
- **M17 — Nationwide network foundation:** search the complete Great Britain station catalogue,
  build over any connected bundled railway route, divide long Local timetables into bounded
  regional workings, retain unrestricted custom Express services, and apply country-scale map
  rendering and simulation budgets.

The original vision roadmap ended at M7. M8 onward are focused extension milestones chosen from its deeper simulation design.

## Current POC scope (Milestone 17 — Nationwide network foundation)

- Select stations from the complete 2,606-station Great Britain catalogue. Nearby markers remain
  available on the map, while **Find station** searches every station by name or CRS code without
  requiring thousands of simultaneous MapKit annotations.
- Preview an automatically routed line over the bundled OpenStreetMap railway graph.
- Discover eligible catalogue stations along that railway in route order, choose intermediate
  calling points before construction, and see the route, forecast and investment update. Existing
  endpoints remain fixed. New infrastructure edits support up to 256 calls per service; automatic
  Local workings remain split into much smaller regional zones so simulation stays responsive.
- Choose **Conventional** or **High speed** while previewing each new line. High speed is a
  new-build choice rather than a retrofit: the line becomes dedicated infrastructure while
  retaining the same routed OpenStreetMap geometry.
- Review distance, estimated passenger demand, track and infrastructure, station construction,
  initial rolling stock, total upfront investment, available balance, and any funding shortfall
  before building.
- Build a dedicated 215 mph high-speed railway with premium facilities at its endpoints,
  high-speed trainsets, fixed Express operation, and double track. Its violet route treatment,
  **HIGH SPEED** map badge, premium station markers, and distinct trains keep it recognisable.
- Confirm construction and watch the route appear.
- Operate up to 512 locally saved services and choose hourly, half-hourly, or quarter-hourly service
  (1, 2, or 4 scheduled trains per hour and the same number of visible trains in this POC).
- Tap the network identity in the top-left HUD to open a bounded portrait line directory. Every
  service has a stable number, colour and operating symbol; selecting one frames its route and
  opens its existing train and service controls. The directory scrolls without taking map gestures
  away from the unobscured area.
- Merge two completed conventional services that share exactly one outer terminal into one linear
  through service. Either source may already span several joined corridors, so the result can be
  extended repeatedly at either end. The selected primary line supplies the resulting frequency and
  Local/Balanced/Express pattern. Where the source services differ, the join preview proposes the
  required changes instead of blocking: the longer train formation and stronger track capacity
  are preserved, and every shorter fleet or weaker corridor is upgraded at the normal capital
  price. A scrollable review sheet itemises each automatic change, its cost, the ordered
  outer-terminal route and the fact that the operation cannot be undone. Career joins require the
  full quoted funding; Zen joins record the same investment against the unlimited budget.
- Keep every paid physical corridor after the merge without rebuilding track or stations. The
  selected primary service retains its stable number, colour and active trains; the secondary
  service is removed and all of its purchased trainsets become owned spares on the through
  service. Matching assets create no purchase, while quoted formation or infrastructure upgrades
  increase the corresponding lifetime spend and network value by the amount charged. Every weaker
  retained corridor is quoted by named segment and upgraded exactly once. Untouched primary fleet
  presets expand across the enlarged route; deliberate custom train plans keep their existing
  terminals and calls until the player edits them.
- Tap any active train on a completed conventional service with at least three built stations and
  open **Edit plan**. Choose either end terminal independently from the service's existing
  stations, reverse the service orientation if desired, and set that train to Local or Express.
  Local trains call at every existing station between their chosen terminals; Express trains keep
  both terminals mandatory while allowing any intermediate calls to be included or skipped.
- Give different active trains on the same railway different terminals and calls, including after
  two services have been joined. Trains turn back at their own terminals, stop only at their own
  calls, and feed those exact paths into passenger markets, platform throughput, capacity,
  crowding, wait times, reliability and operating forecasts. Editing a stopping plan is immediate
  and free because it changes the timetable rather than building infrastructure.
- Keep long default Local services credible. The automatic planner targets roughly 60-minute
  regional workings and enforces a 75-minute, 90 km and 12-call maximum. Adjacent regional
  workings share a transfer station, so every feasible selected call remains connected without a
  local train attempting an implausible end-to-end national journey. Balanced timetables combine
  those regional workings with full-route Express trains.
- Keep player-defined Express services unrestricted by distance. A player can deliberately run a
  London–Edinburgh or Aberdeen–Penzance Express, choose its terminals and add selected calls along
  the retained railway. The same overlong terminal choice is rejected for a Local train with an
  explanation to shorten it or switch to Express.
- Draw only a bounded, viewport-relevant set of candidate stations, trains and routes. Long route
  geometry is cached and simplified at country and regional zoom levels, offscreen content is
  culled, and candidate stations refresh when camera movement ends rather than on every gesture
  sample. A restored network is framed once from bounded per-line geometry summaries; later line
  additions and joins no longer rebuild one country-wide coordinate array or reset the player's
  camera. The logical timetable can contain every regional working while the animated map keeps a
  bounded set of representative train markers.
- Treat the national station catalogue as reference data rather than 2,606 active settlements.
  Passenger, population and happiness detail is calculated for stations in the player's railway;
  compact test/scenario catalogues retain their existing whole-catalogue behavior. Transfer
  candidates are indexed by interchange instead of comparing every market with every other
  market; compact hubs remain exhaustive while exceptional hubs retain the best 2,048 detailed
  one-change candidates. Accessibility keeps exact connected-station reachability and destination
  importance, while national detailed route quality is sampled deterministically from at most 128
  destinations per origin. Train movement reuses cached topology; railway graph loading remains
  lazy; and route caches are bounded by both entry count and graph-path size.
- Keep four stable timetable-slot plans for every service. Hourly, half-hourly and quarter-hourly
  operation activates the first one, two or four plans respectively; reducing frequency preserves
  the dormant plans for a later increase. The Local, Balanced and Express fleet controls remain
  quick presets. Applying one after customisation asks for confirmation because it resets all four
  plans to the selected preset.
- Open **Edit stops** on a completed single-corridor conventional service to add another eligible
  station along its retained corridor. A named, priced confirmation protects the atomic,
  permanent change, which charges only for a station that is not already part of the player's
  network. Stop edits on a merged through service are deferred.
- At local or regional map scale, stations that can be inserted into a nearby completed service
  gain a green **+** marker and a forgiving 64–72 point tap target. Tapping one performs the exact
  OSM-anchor check on demand, then presents every compatible service, the resulting ordered calls,
  stopping-pattern effect, price and affordability before anything changes.
- Watch local trains stop and dwell at every selected station. Balanced timetables give the
  intermediate calls to their local trains while express trains pass through; endpoints retain
  the full advertised frequency.
- Give every station level real platform throughput. Each platform handles four aggregate train
  calls per hour, and every service needs an arrival and departure call at both endpoints. A
  one-platform Halt can therefore sustain one half-hourly line; higher frequency or multiple lines
  sharing a small station are reduced proportionally until the station grows.
- Compare scheduled and effective departures on each line, see the limiting station by name, and
  inspect handled, scheduled, and available train calls in station details. A fixed orange warning
  symbol makes constrained stations discoverable without relying on colour alone.
- Set each conventional line to the **Local**, **Balanced**, or **Express** fleet preset. Balanced
  assigns a deterministic mix of local and express trains when at least two trains are running;
  fixed L/X train badges make each train's current stopping role visible on the map. Individual
  plans can then be refined without changing the other trains.
- See frequency, service mix, and infrastructure combine into a deterministic track-flow,
  reliability, and journey-time forecast. Congested routes receive a dashed map halo and affect
  passenger attraction, happiness, and the operating forecast.
- Upgrade a constrained single-corridor conventional line from single track to a £8m passing loop
  and then to double track.
  A passing loop creates a visible midpoint operating section where a local waits and an express
  can overtake; double track permits overtaking route-wide. Upgrades add network value and track
  upkeep, and Career purchases require available funding. Track upgrades on a merged through
  service are deferred.
- Track the trains owned by each line. Increasing frequency buys any additional rolling stock
  required; reducing frequency retains the purchased fleet for a later increase.
- Choose one real purchased formation for every trainset on a line. Conventional services support
  2, 4, 6, 8, 10, or 12 cars; dedicated high-speed services support 6–12 cars. Each carriage adds
  40 seats. The route preview recommends a formation for roughly 80% peak loading while leaving
  the final decision to the player, and updates crowding, unserved demand, capital cost, and the
  passenger forecast immediately.
- Permanently add two cars to every trainset owned by a completed line. The atomic fleet-wide
  purchase increases direct and connecting capacity, network value, variable energy use, and
  distance-based maintenance; Career mode requires full funding and Zen records the spend against
  its unlimited budget.
- Pause, accelerate, select, and follow trains.
- Inspect aggregate passenger usage, capacity, wait time, and service feedback for each line.
- Inspect station activity, potential and served journeys, unserved demand, direct connections, and permanent evolution progress.
- Grow served stations automatically through six visual levels—Halt, Local Station, Town Station,
  Major Station, Interchange, and Terminus—with increasing platform throughput and upkeep. A
  promotion releases its additional service capacity immediately for the following forecast.
- Track a clearly labelled synthetic gameplay population for every settlement connected to the
  completed network. Better local happiness and access to more destinations create bounded
  population growth at operating-day boundaries; that growth modestly increases the following
  day's passenger-demand potential without creating a runaway feedback loop.
- Read the latest population change and demand effect in station details, the compact total in
  the network pulse, and a bounded 120-day population trend and recent history in Statistics.
- Choose **Career mode**, which starts with £150m and enforces upfront spending, borrowing,
  solvency, and bankruptcy, or **Zen mode**, which provides an unlimited budget while retaining
  the same financial statistics.
- Compare projected passenger-fare revenue with energy, rolling-stock maintenance, track
  maintenance, station maintenance, loan interest, and principal repayments. The dashboard
  separates operating result, profit after interest, and projected cash change. High-speed rail
  receives 1.35× fare revenue while paying 2× energy, 1.75× rolling-stock maintenance, 2×
  track upkeep, and an additional £5,000 per premium station per day.
- Pay construction and initial-fleet costs when a line is confirmed, and pay for extra trains
  when a higher service frequency needs more rolling stock. Track and infrastructure use the
  route's indicative cost; every selected station not already in the network adds £2m of station
  construction, and a conventional six-car train costs £4m. Shorter and longer formations scale
  that six-car price in direct proportion to their carriage count.
- Price a high-speed line at 3× the conventional track quote, £20m for each endpoint that is
  not already a premium high-speed station, and £20m per six-car high-speed trainset. Longer
  formations scale that baseline price proportionally. The preview shows the conventional track
  reference for comparison.
- Borrow standard £40m loans in Career mode and make early principal repayments of up to £10m
  at a time, limited by available cash and outstanding debt.
- Read a compact network pulse showing Career cash (or an unlimited Zen budget), projected
  daily cash change or result, gross network value, happiness, passengers, unserved journeys,
  high-speed prestige, and lifetime operating result.
- Open the finance dashboard to inspect debt, gross network value, net company value,
  commercial viability, and lifetime tracked construction, rolling-stock, and interest totals.
- Measure local happiness for each constructed-network settlement and a demand-weighted global
  network score without continuously simulating thousands of unbuilt catalogue references.
- Explain happiness through reachable destinations, destination importance, journey time, frequency, reliability, and crowding, using the weights in the game design.
- Generate deterministic one-change passenger demand throughout an arbitrary active network.
  Direct services take priority; otherwise the best single-interchange itinerary is selected.
  All connecting markets share residual peak and off-peak seats fairly, occupy capacity and earn
  fare revenue on both legs, affect each service's crowding and feedback, and add transfer activity
  at the shared station. Adding an unrelated third service no longer removes an existing journey.
- Switch the network dashboard between Finance, Happiness, and Prestige. Prestige is derived
  from completed high-speed infrastructure rather than stored separately: each completed
  corridor contributes 15 points and each distinct premium endpoint contributes 5, capped at
  100. Shorter high-speed journeys also feed the normal accessibility and happiness calculation.
- Toggle a colour-and-text-keyed accessibility heatmap from the Happiness view.
- Inspect connected or disconnected station markers to see their local score and the strongest positive and negative reasons behind it.
- Resume the railway class, railway and train positions, premium stations, and financial state
  after relaunching the game; deterministic high-speed prestige is recomputed from the restored
  completed network.
- Follow a deterministic day/night clock with clear, overcast, rain, and fog treatments. The
  simulated dawn/day now selects MapKit's light appearance while dusk/night selects its dark
  appearance. The atmosphere is cosmetic, never intercepts map gestures, pauses with the railway,
  and can be disabled independently from weather in Settings.
- Enable optional procedural railway sound effects for line openings, station or infrastructure
  upgrades, achievements, visible scheduled-station fare collections, and occasional deterministic train
  horns. Sound is off by default, respects the ambient audio session, queues short cues without
  interrupting them, and releases the audio session when the queue is empty.
- See an immediate, rising `+£…` fare-revenue reward whenever an in-view train reaches a scheduled station.
  The amount allocates the existing daily fare projection across scheduled journeys and does not
  duplicate the operating-day cash settlement.
- See a fixed-size construction-frontier marker and restrained sparks while a line is being
  built. Zooming close to a train reveals its exact purchased 2–12-car formation; zooming out
  returns to the compact sprite. A train's visible length no longer changes when demand changes.
  Annotation bounds remain invariant so stations, trains, and construction markers do not drift.
- Complete a three-step first-launch quick start, replay it from Settings, and move directly from
  the final step into the real line builder.
- Unlock seven cross-game achievements and play two POC-sized scenarios: **Southern Starter** and
  **High-Speed Future**. Starting a scenario explicitly replaces the current railway; ordinary
  New Career or New Zen games leave any active scenario.
- Inspect a saved, bounded 120-operating-day statistics history containing passenger, happiness,
  operating-result, network-value, prestige, and synthetic-population summaries.
- Use the game at accessibility text sizes and with VoiceOver, Reduce Motion, Reduce Transparency,
  Increase Contrast, and Differentiate Without Color. Happiness heatmaps retain symbol and line
  treatments rather than relying on colour alone.
- Protect the public-beta build with deterministic multi-year simulation soaks, bounded-work and
  performance benchmarks, schema 1–12 save compatibility and damaged-save recovery tests, plus
  portrait, appearance, Dynamic Type, and modal-presentation rendering checks.

Train movement is deliberately time-compressed for evaluation: even a long route takes no more
than about 32 seconds each way at 1× speed (or roughly 11 seconds at 3×). One synthetic operating
day lasts 30 seconds at 1×. Opening a newly constructed line starts a fresh operating day so its
new network forecast is not credited for time before it opened; changing a timetable preserves
the current day's progress.

Passenger demand is a deterministic, synthetic aggregate intended for gameplay tuning. It
estimates latent demand from station profiles and distance, then responds to effective service frequency,
each line's purchased seats per train, operations reliability, and a tightly bounded
settlement-population multiplier. Each connecting market uses at most two services and one
interchange, but many such markets can coexist and share capacity across a larger network. The
network headline remains train boardings, so each connecting passenger contributes one ride to
each leg, while station and line details expose the unique transfer journeys separately. It does
not model individual passengers or claim to reproduce real-world ridership.

Operating and capital economics are synthetic POC tuning values. Career mode deducts upfront
construction and rolling-stock purchases, blocks purchases that cannot be funded, settles daily
operating and loan cash flows, and enters insolvency whenever cash is below £0. A Career company
that finishes seven consecutive operating days with negative cash becomes bankrupt; returning to
a nonnegative balance during the grace period resets the count. Zen mode never limits spending.
Six-car trains preserve the earlier cost and operating forecast exactly; formation-dependent asset
value, energy, and variable maintenance scale from that baseline, while fixed trainset overhead
remains tied to the number of assigned trains.

Real demographic data, employment and tourism growth, demand splitting across competing routes,
journeys requiring more than one change, manual track alignment, signalling, and production
artwork remain future work. The simulation chooses one deterministic best direct or one-change
itinerary for each market across the trains' actual calling patterns; it does not yet split demand
across alternative itineraries.
Operations reliability is a deterministic forecast derived from service frequency, pattern, and
track capacity. Random incidents, cancellations, signalling blocks, and shared-track conflicts
between separate player lines remain future work.

## Testing Milestone 2 manually

1. Keep the existing save, or use **Game menu → New Zen Game** only if you want to watch progression from the beginning. Build two lines that share one station so the shared station has two direct destinations.
2. Set the speed to **3×**. One synthetic operating day then completes every 10 real seconds; pause should stop both trains and operating-day progress.
3. Watch the network pulse update passengers, projected operating result, unserved demand, station upkeep, operating day, and lifetime operating result.
4. Tap a station marker. Its card shows level, platform count, daily upkeep, lifetime passenger visits, and progress or requirements for the next level. The POC passenger thresholds are 10k, 50k, 200k, 600k, and 1.5m visits. Interchange and Terminus also require at least two direct destinations. Upgrades happen at most one level per operating day and produce a banner plus a larger marker.
5. Tap a train and change its service frequency. Hourly, half-hourly, and quarter-hourly service show 1, 2, and 4 trains respectively. Confirm that shorter waits and higher ridership are balanced by higher train costs, and that both the line result and network pulse change immediately.
6. Background or close the app, then reopen it. The two lines, frequencies, train positions, station levels, operating-day progress, and lifetime economy should return.
7. Pan and zoom from every unobscured part of the map, including the strip below the bottom cards. Only the visible controls themselves should reserve touches.

## Testing Milestone 3 manually

1. Open an existing two-line save, ideally with two lines sharing a station. The compact network pulse now includes the global happiness score.
2. Tap the network pulse, select **Happiness**, and confirm that it shows all six weighted happiness components, connected-settlement coverage, reachable pairs, and the strongest network feedback.
3. Turn on **Accessibility heatmap**, close the dashboard, and pan or zoom the map. Coloured circles should stay anchored to their station locations, railway lines and station markers should remain clear above them, and the map should still respond anywhere outside visible controls.
4. Tap a connected station. Its card should show a non-zero local happiness score, reachable destinations including any through connection, a component breakdown, and plain-language strengths and weaknesses.
5. Tap a disconnected station while the heatmap is visible. It should still open for inspection, score zero, and explain that it needs a rail connection.
6. Tap a train and change its service frequency. Reopen the station and network cards: frequency should improve with diminishing returns, while crowding and the passenger/economy trade-offs can also change.
7. Pause and move trains without changing the network. Happiness should remain stable. Close and reopen the app; the same saved lines should deterministically recreate the same happiness results without a save migration.

## Testing Milestone 4 manually

1. Launch with an existing Milestone 3 save if available. Its lines and operating history should
   remain intact, and **Game menu** should identify it as a Zen game after schema migration.
2. Choose **Game menu → New Career Game** and confirm the warning. The empty company should
   start with £150m; the same menu can start a new unlimited-budget Zen game.
3. Preview a line. Check the separate track, station, and initial-fleet costs, total upfront cost,
   available balance, and shortfall. Career's **Build line** button must remain disabled until the
   quote is affordable. Before borrowing, check that **Borrow £40m** discloses its APR, term, and
   first scheduled payment; tapping it should add funding when a loan is available.
4. Build the line and confirm that Career cash falls by the quoted total. Tap the network pulse:
   Finance should open first and show revenue, all four operating-cost categories, interest,
   principal, profit, cash change, debt, gross network value, and net company value. Switching to
   Happiness should retain the Milestone 3 dashboard and heatmap control.
5. Run at **3×** through at least one operating day. Cash should move in the direction and amount
   shown by projected cash change, while lifetime operating, capital, and interest totals update.
6. In Career Finance, borrow a standard loan and verify that cash and debt each rise by £40m.
   Use the **Repay** button and verify that its displayed amount—and the fall in cash and
   principal—is £10m or the smaller available cash/outstanding balance.
7. Tap a train and raise frequency. The card should show running and owned trains, the next fleet
   purchase, and separate energy, rolling-stock maintenance, and track-maintenance costs. A paid
   increase should reduce Career cash; lowering frequency should retain the owned trains.
8. Close and reopen the app. Mode, cash, loans, owned fleet, lifetime finance totals, insolvency
   progress, lines, trains, and the prior operating state should restore.
9. Optional bankruptcy stress test: leave a loss-making Career company below £0 at **3×**. The
   dashboard should count down the grace period; recovery to £0 or more resets it. Seven
   consecutive negative-cash operating days should replace normal controls with the bankruptcy
   card and confirmed options for a new Career or Zen game.

## Testing Milestone 5 manually

1. For the quickest unrestricted test, choose **Game menu → New Zen Game**, build one line, and
   wait for construction to complete. An older save should instead migrate with **Balanced**
   service on **Single track**, without losing its trains, finances, or progress.
2. Tap either train. Scroll the bottom card and confirm that **Line operations** contains the
   Local/Balanced/Express selector, service mix, track flow, reliability, and an infrastructure
   action. The map must still pan and zoom everywhere outside the visible card and controls.
3. Choose **Local**, then **Express**. The train badges should change from L to X, the line's thin
   route pattern should change, and journey time, passengers, reliability, happiness, and the
   financial forecast should recalculate immediately. Return to **Balanced** to see one L and one
   X train on the default half-hourly service.
4. On single track, Balanced should explain that expresses are held behind local trains. Tap
   **Build passing loop** and leave the game at **1×**. A wider midpoint section and **LOOP** badge
   should appear; within a few seconds the X train should catch the waiting L train and show a
   yellow bolt/overtaking halo as it passes.
5. Reopen the train card and choose **Add second track**. The whole line should become visibly
   wider with a centre split and a **2 TRACKS** badge. Track flow and reliability should improve,
   while track maintenance and network value increase.
6. Raise frequency to **Every 15 minutes**. Confirm that four trains run, Balanced assigns two L
   and two X services, and congestion reacts differently on single track, a passing loop, and
   double track. Lowering frequency must retain the owned rolling stock as before.
7. In Career mode, repeat an upgrade with insufficient cash: the purchase must be refused without
   changing the track or balance. Borrowing enough funding should then allow it; Zen should record
   the same upgrade value without limiting the budget.
8. Close and reopen the app. Service pattern, track capacity, train positions, cash, and operating
   progress should restore. The same network should recreate the same congestion and reliability.

## Testing Milestone 6 manually

1. Keep the simulator or device in portrait. For the fastest unrestricted test, choose
   **Game menu → New Zen Game**, tap **Build a line**, and select two stations that are not
   already connected. The POC still permits only one service for a station pair.
2. On the new-line preview, switch **Railway class** between **Conventional** and **High speed**.
   The selected endpoints and routed map geometry must not move. High speed should instead show
   a shorter estimated journey, dedicated-infrastructure description, 215 mph capability, and
   **Build high-speed** action. Switching back must restore the conventional quote and journey.
3. With two endpoints that are not already premium, verify the high-speed quote: dedicated track
   is exactly 3× the displayed conventional track reference, premium station facilities total
   £40m (2 × £20m), and the initial half-hourly fleet totals £40m (2 × £20m). The first
   corridor should preview **+25** prestige. The total upfront amount must equal those categories.
4. Build the high-speed line. During construction the card should describe a high-speed landmark;
   on completion the map should show a violet dedicated route, **HIGH SPEED** badge, H-marked
   premium endpoint stations, and distinct high-speed trains. At 1×, compare their movement
   with a conventional line if one exists; pause and 3× must still behave normally.
5. Tap a high-speed train and scroll its portrait card. Confirm it identifies a **215 mph
   high-speed service**, **Express-only operation**, dedicated double track, premium stations,
   premium fare revenue, and network prestige. There must be no Local/Balanced selector or
   passing-loop/double-track purchase action for this fixed high-speed configuration.
6. Tap the network pulse. **Finance** should separate the included high-speed fare premium and
   premium-station upkeep while retaining energy, rolling-stock maintenance, track upkeep,
   finance, and company-value rows. **Happiness** and connected-station cards should use the
   shorter high-speed journey in their journey-time/accessibility result.
7. Select **Prestige**. After the first corridor completes it should show **25/100**, one completed
   corridor, two premium stations, and the **High-speed pioneer** tier. If the second POC line is
   another high-speed corridor sharing one endpoint, its preview should charge only one new £20m
   premium facility and add **+20** prestige; completion should produce 45/100, two corridors,
   three premium stations, and the National tier.
8. Repeat the preview in Career mode if affordability needs testing. The high-speed total must be
   deducted atomically when built, **Build high-speed** must remain disabled while the quote is
   unaffordable. Use one or more existing £40m loans to close the shortfall where the three-loan
   limit permits. Cancelling or attempting an unfunded purchase must not change cash or the network.
9. Background or close the app, then reopen it. The high-speed class, fixed Express/double-track
   operation, premium endpoints, trains, cash and operating progress must restore. Prestige must
   deterministically return from the completed restored network; a schema 1–6 save should instead
   retain all of its earlier data while its existing lines migrate as Conventional.
10. Repeat the preview and train-card checks at an Accessibility Dynamic Type size and with
    VoiceOver. The portrait cards should scroll without reserving the unobscured map, all class
    choices and actions should remain at least 44 points, and VoiceOver should announce the
    selected railway class, dedicated high-speed route and rolling stock, premium stations,
    215 mph capability, and prestige. Pan and zoom anywhere outside the visible controls.

## Testing Milestone 7 manually

1. Install or launch the updated app in portrait. Existing schema 7 saves should open with their
   railway, finances, trains, station progress, and operating-day state intact. A clean install
   should show **Quick Start** once; sound must initially be off.
2. Work through all three Quick Start steps. **Build a line** on the final step must close the
   guide and immediately show **Choose a starting station**. Cancel building, then use
   **Game menu → Settings & guide → Replay quick start** to confirm it can be repeated.
3. Open **Game menu → Settings & guide** and disable **World effects**. Close Settings: the
   world-status badge and atmosphere should disappear immediately. Re-enable it: the badge must
   show the in-game clock and phase. Dawn/day must use the light MapKit basemap and dusk/night the
   dark basemap, independently of the phone's appearance. During the two-hour dawn and dusk periods,
   the atmospheric light should change continuously and the native basemap palette should fade
   through the twilight midpoint rather than snap. With **Weather** enabled the badge also shows
   the current condition; **Clear** intentionally has no precipitation particles. Disable Weather to remove
   that condition and any rain, fog, or overcast treatment while retaining the clock and phase.
   At 3× a six-hour weather period lasts about one real minute. Pause the railway and confirm the
   badge clock stops advancing. In every state, drag and zoom from under the badge and confirm
   lines, trains, station markers, attribution, and all map gestures are unaffected.
4. Enable **Sound**, keep an operating endpoint visible, and run at **3×**. Every terminal arrival
   in view should hold a `+£…` reward still and fully readable for 1.5 seconds, then rise and fade
   over 0.5 seconds. It should play a short cash-register sound with a drawer/clack followed by a
   metallic ching, rather than two clean electronic tones; panning the endpoint fully offscreen
   should suppress both. Keep running for several arrivals to hear a deliberately
   occasional horn. Then open a line, upgrade a station or track, and unlock an achievement.
   Confirm queued cues do not cut one another off or stop other audio. Disable Sound and relaunch;
   visuals should remain but the app should be silent.
5. Build a line at 1× and inspect its construction. The frontier badge and sparks must stay
   anchored to one map coordinate while panning and zooming; completed station markers must not
   move. Zoom closely into a train until individual carriages appear. A lightly used Local should
   be short, while a busy long-distance Express or high-speed service should be longer; counts are
   always even and range from 2 to 12. Pinch around the transition and confirm it does not flicker,
   reverse at a terminal and confirm the centered formation does not jump, and verify map gestures
   still begin over the visual carriage tail. With Reduce Motion enabled, the fare reward becomes
   static and sparks, rain, fog, pulses, and overlay transitions should be static or subdued.
6. Open **Game menu → Progress & scenarios**. Achievements should show consistent progress; an
   unlocked item must remain **DONE** with a full progress bar after starting another railway.
   The unlock banner should appear once and the result should survive relaunching.
7. In **Scenarios**, inspect both challenges, tap **Start scenario**, and first cancel the warning
   to prove the railway is unchanged. Then start it and confirm a fresh game opens in the stated
   mode. Only the active scenario should show live objective progress. Completing it should show
   a completion banner; replayed completions remain recorded separately from the current run.
8. Start an ordinary **New Career Game** or **New Zen Game** after entering a scenario. Reopen the
   scenario screen and confirm no scenario is still marked active, while earned achievements and
   completed scenarios remain in the player profile.
9. Run at 3× through at least two operating days and open **Statistics**. Counts and the latest-day
   summary should update once per day. Close and reopen the app to confirm they restore; starting
   a new game should reset this railway-specific history without erasing profile achievements.
10. Repeat Quick Start, Settings, Achievements, Scenarios, and Statistics using the largest
    Accessibility text size, VoiceOver, Dark Mode, Increase Contrast, Reduce Transparency, and
    Differentiate Without Color. Content must scroll rather than clip, controls must remain at
    least 44 points, completed states must not rely on colour, and the unobscured map must still
    pan and zoom.

## Testing Milestone 8 manually

1. In Xcode, select the **TrainTrackTycoon** scheme and any portrait iPhone simulator, then choose
   **Product → Test**. The run should finish with no failures. The new **Game session deterministic
   soak**, **Persistence hardening**, **Persistence recovery**, **Game presentation policies**, and
   **SwiftUI render smoke** suites cover the Milestone 8 regressions automatically.
2. In the Test navigator, run **SimulationPerformanceBenchmarks** on its own. Xcode should report
   five measurements for both the maximum-network daily-settlement benchmark and the
   representative 4,096-point route-sampling benchmark. These establish comparison data without
   assuming that every development Mac or simulator has the same speed.
3. Install this build over the Milestone 7 build rather than deleting the app. Open the existing
   railway and verify its lines, trains, cash or Zen budget, station progress, statistics, active
   scenario, sound setting, and operating-day position all return unchanged.
4. Run a two-line network at **3×** for at least ten operating days. Pan, pinch, select trains and
   stations, open and close the network dashboard, and change a service frequency while it runs.
   Trains must keep moving smoothly, statistics must advance once per day, retained history must
   stay ordered, and no reward, horn, or station-upgrade event should repeat unexpectedly.
5. Pause, background, and force-quit the app at three different points: while a train is moving,
   immediately after a timetable change, and just after an operating day completes. Relaunch each
   time and confirm the saved state is readable and resumes without duplicate lines, trains,
   financial settlements, or presentation events.
6. On a narrow portrait simulator such as **iPhone SE (3rd generation)**, test the game menu and
   New Career confirmation in Light and Dark Mode, then repeat with an Accessibility text size.
   Overlays and bottom panels must scroll rather than clip, only one modal should be visible, and
   the unobscured map above and below the controls must still pan and zoom.
7. Finish with a normal new Career and new Zen game flow. Cancel each destructive confirmation
   once before confirming it, build a first line, and relaunch. This checks that the QA refactor
   has not changed modal priority, bottom-panel selection, or fresh-save creation.

## Testing Milestone 9 manually

1. Install this build over the previously tested Milestone 8 build without deleting the app.
   Open the existing railway and confirm its lines, trains, finances, station progress, and
   Statistics history still restore. Existing connected stations should start from their
   synthetic baseline population rather than losing the railway or save.
2. Open a connected station's details. Under **Synthetic gameplay population**, confirm you can
   see its current population, latest change, passenger-demand multiplier, and a plain-language
   explanation of its growth conditions. A disconnected catalogue station should say that it has
   no rail-led growth.
3. Resume the railway at **3×** and watch at least three operating days finish. Population should
   change only once per completed day: the station panel and compact **GAME POP** value should
   update together. Pause part-way through a day and confirm neither advances while paused.
4. Build a second line that shares a station with the first, then run several more days. Compare
   the shared station with an endpoint that reaches fewer destinations. Better access and local
   happiness should produce stronger—but still small and steady—growth, and its demand multiplier
   should rise gradually rather than jump dramatically.
5. Open **Game menu → Statistics → Population**. Confirm the total matches the network pulse, the
   trend chart advances once per operating day, and the recent list shows the newest five days in
   order. Close and relaunch the app; the current populations, latest changes, and chart history
   should restore unchanged.
6. Start a new Career or Zen game, accepting the destructive confirmation. The old railway's
   population and history should clear. Build a new first line and confirm its endpoints begin at
   their baselines with zero latest growth until the first operating day completes.
7. Repeat the station panel and Population Statistics view on a narrow portrait iPhone and with
   an Accessibility text size. Content should scroll rather than clip, VoiceOver should identify
   the figures as synthetic gameplay population, and the unobscured map should still pan and zoom.

## Testing Milestone 10 manually

1. Open a connected station in both the daytime and night-time map appearances. Confirm that the
   green population and positive-growth text remains clearly readable against the station card in
   Light Mode, Dark Mode, and Increase Contrast. Dismiss the card: on a completed two-line POC
   network, the compact budget/result/network-value card should return close to the bottom of the
   screen, without an inactive **POC network complete** card pushing it upward. Pan and zoom above
   and below the visible cards to confirm the unobscured map remains interactive.
2. For a clear transfer test, start a new Zen game and build **Purley–East Croydon**. Open its line
   details and note the passengers, projected revenue, and connecting-passenger value. With only
   one line, the connecting value must be zero or absent.
3. Build **East Croydon–London Victoria** as the second line. No transfer demand should appear
   while it is under construction. When it opens, passengers travelling Purley–London Victoria
   should change at East Croydon: both line cards should report connecting passengers, and the
   shared station should report interchange demand. The two outer stations should not claim to be
   the interchange.
4. Compare both lines' passengers and fare revenue immediately before and after the second line
   opens. Both legs should gain the connecting boardings and revenue. The compact network headline
   remains **RIDES/DAY**, so each transfer passenger is correctly counted once on each train leg;
   the interchange figure counts each connecting journey once.
5. Change one leg to **Hourly** while leaving the other at a higher frequency. Transfer throughput
   should fall or remain bottlenecked, and the busier leg must never carry more than its displayed
   capacity. Raise the constrained leg to **Every 15 minutes** and confirm the connection and
   financial forecast recalculate immediately. Reliability and crowding feedback should follow the
   loaded legs rather than changing only at the interchange.
6. Let at least one operating day complete at **3×**. East Croydon's station visits/evolution
   should include its transfer activity, while happiness and subsequent synthetic population
   growth continue to update only at normal operating-day boundaries.
7. As a negative check, start fresh and build two lines that do not share a station, such as
   **London Victoria–Clapham Junction** and **East Croydon–Purley**. Neither line nor any station
   should show connecting journeys.
8. Close and reopen the shared-interchange game. The lines and durable progress should restore,
   and the same connecting forecast should be deterministically recomputed without a save-format
   migration. Repeat the line and station cards on a narrow portrait iPhone, at an Accessibility
   text size, and with VoiceOver; values should remain labelled and scroll rather than clip.

## Testing Milestone 11 manually

1. Install this build over the tested Milestone 10 build without deleting the app. Open the saved
   railway and tap one of its trains. Every migrated line should report **6 cars** and **240 seats
   per train**, with the same passenger, operating-cost, network-value, cash, and lifetime-spend
   figures it had before migration. Close and reopen once to confirm the migrated save is stable.
2. Start a new Zen game and preview a conventional line. Under **Train formation**, confirm the
   recommendation is selected initially. Use the stepper through 2, 4, 6, 8, 10, and 12 cars:
   seats per train must change by 80 each step, while peak load, daily seats, unserved journeys,
   initial-fleet cost, and total upfront investment update immediately. The recommendation should
   remain visible when you deliberately choose a different length.
3. Switch the same preview to **High speed**. Its choices must be limited to 6, 8, 10, and 12
   cars; switching back to Conventional should keep any still-valid choice. Confirm a six-car
   conventional train uses the historical £4m baseline and a six-car high-speed train uses the
   historical £20m baseline, with other lengths scaling proportionally.
4. Build the line, wait for it to open, and tap a train. Its card should show the purchased car
   count, seats per train, owned trainsets, fleet seats, peak passengers against that line's real
   capacity, and formation-scaled energy and maintenance. Zoom close enough to reveal individual
   carriages and count them; pan and change demand or service pattern and confirm the purchased
   length stays fixed.
5. Tap **Add 2 cars to every train**. The displayed price must cover every owned trainset, the
   card and close-zoom train should gain exactly two cars, and seats per train should rise by 80.
   Passenger capacity, crowding/unserved feedback, operating cost, network value, and finance
   totals should recalculate immediately. Continue to 12 cars and confirm the action becomes a
   clear maximum-formation state.
6. Increase frequency after lengthening. Any extra trainsets should be bought at the line's current
   formation price; lowering frequency should retain both the owned trainsets and their length.
   On another line, buy the frequency first and lengthen afterward—the final fleet ownership cost
   should not depend on which order you used.
7. Build two lines sharing a station and create connecting demand. Make one leg short and the other
   long: transfer riders should remain constrained by the residual capacity of both legs. Lengthen
   only the bottleneck leg and confirm connecting boardings and both lines' forecasts update
   without either train exceeding its displayed capacity.
8. In Career mode, attempt a fleet extension that costs more than available cash. It must show the
   funding error without changing cash, car count, seats, fleet value, or lifetime spend. Arrange
   enough funding and retry; the complete fleet-wide purchase should then happen once. Relaunch and
   confirm every line's exact formation, capacity, position, finances, and operating forecast
   restore unchanged.
9. Repeat the preview and train card at a 320-point portrait width, at an Accessibility text size,
   in day and night appearances, and with VoiceOver. Formation choices, seats, recommendation,
   costs, and the fleet-wide upgrade should remain labelled and scroll instead of clipping; the
   unobscured map above the cards should continue to pan and zoom.

## Testing Milestone 12 manually

1. Install this build over the tested Milestone 11 build without deleting the app. Open the saved
   railway and confirm its station levels, passenger-visit progress, lines, formations, cash, and
   lifetime spending are unchanged. Capacity is derived from the saved station levels, so there is
   no migration charge or new save field.
2. Start a new Zen game and build one line at the default half-hourly frequency. Open either
   endpoint while it is still a one-platform **Halt**. Its **Platform throughput** panel should
   show 4 scheduled calls/hour, 4 handled, and capacity 4, with no warning. The train card should
   show 2 scheduled and 2 effective departures/hour.
3. Increase that line to quarter-hourly service while an endpoint is still a Halt. The endpoint
   should show 8 scheduled calls/hour but only 4 handled; an orange warning symbol should appear
   on its fixed station marker. The train card should show 4 scheduled but 2 effective
   departures/hour, name the limiting station, and use the station-capacity explanation rather
   than telling you to buy longer trains.
4. Run at **3×** until the station automatically grows to **Local Station**. The upgrade banner
   should say 2 platforms and capacity 8 calls/hour. Reopen the station and train cards: the
   quarter-hourly service should now deliver all 4 departures/hour, with passenger, wait,
   happiness, revenue, and warning state recalculated immediately.
5. For the hub check, start fresh and build two half-hourly lines that share a station before an
   operating day completes—for example **London Victoria–East Croydon** and **East
   Croydon–Purley**. While the shared station is a Halt it requests 8 calls/hour but can handle 4,
   so both lines should fairly deliver 1 effective departure/hour. Outer one-line Halts remain at
   their full 2 departures/hour. Building the lines in the opposite order must not favour either.
6. Inspect the shared station and both trains. The hub card should identify the platform
   bottleneck, and both train cards should name the hub. Connecting riders must remain bounded by
   both effective legs; the network passenger and operating-result forecasts should be lower than
   after the hub grows to Local Station and releases all 8 calls/hour.
7. Lengthen a constrained train and change its service pattern. Seats, costs, and the normal
   operations forecast should update, but neither action may bypass an endpoint platform limit.
   Reducing the chosen frequency enough should clear the warning without changing the station
   level.
8. In Career mode, let a promotion complete and confirm the existing next-tier station upkeep and
   network value begin in the new forecast. It must not deduct a new construction purchase or
   alter lifetime construction/rolling-stock spend. Close and reopen: scheduled/effective
   frequencies and bottleneck warnings should derive to the same values.
9. Repeat the station and train cards at a 320-point portrait width, an Accessibility text size,
   in day and night appearances, and with VoiceOver and Differentiate Without Color. The capacity
   values and warning text should reflow and remain labelled; station warnings must use a symbol,
   and the unobscured map must continue to pan and zoom.

## Testing Milestone 13 manually

1. Install this build over the tested Milestone 12 build without deleting the app. Open the saved
   railway and confirm both existing lines, train formations and positions, station progress,
   finances, statistics and operating-day position are unchanged. No migration purchase or cash
   movement should occur.
2. Start a new Zen game and build a third line. It should preview, construct and operate exactly
   like the first two; the build control should remain available until the twelfth service.
3. Tap the network identity at the top-left of the HUD. **Your lines** should open in the bounded
   bottom area with a stable number, route, status symbol and stop count for every service. Tap a
   row: the map should frame that route, the directory should close and the service's existing
   train controls should open. Reopen the directory and tap the same row again to verify it frames
   repeatedly.
4. Build three half-hourly lines around one small shared station. Inspect the station and each
   train: the limited platform calls should be shared fairly. A service already constrained at its
   other endpoint should release unused hub capacity for the others rather than wasting it.
5. Build **Purley–East Croydon** and **East Croydon–London Victoria**, then add any unrelated third
   service elsewhere. The Purley–London Victoria one-change passengers and East Croydon transfer
   activity must remain present after the third service opens.
6. Create a three-leg chain. The two adjacent pairs should generate their respective one-change
   markets, while a journey requiring two changes should not yet be offered. If a direct service is
   added between an outer pair, it should replace the competing transfer market for that pair.
7. Optional maximum-network stress check: in Zen mode build up to 12 services, set 3× speed, and
   run at least ten operating days while panning, pinching, opening the line directory and changing
   several frequencies. The thirteenth build should be blocked with a clear 12-line-limit message.
8. Force-quit and relaunch the multi-line game. All services, stable line numbers and colours,
   corridor identities, trains, finances and derived passenger connections should return. Reopen
   the directory and verify each row still frames the matching route.
9. Repeat the line directory on a narrow portrait iPhone, in Light and Dark Mode, with an
   Accessibility text size, VoiceOver and Differentiate Without Color. Rows should scroll rather
   than clip, VoiceOver should announce the line number, endpoints, status and stop count, and the
   map above the visible panel must continue to pan and zoom.

## Testing Milestone 14 manually

1. Install this build over the tested Milestone 13 build without deleting the app. Open the saved
   railway and confirm its existing services remain two-stop routes with unchanged trains,
   finances, station progress and operating-day position. No migration purchase should occur.
2. Start a new Zen game and preview **London Victoria–Kent House**. Expand **Calling points**.
   Eligible stations should be listed in railway order, including Brixton and Herne Hill; the two
   endpoints should be fixed.
3. Select Brixton and Herne Hill. Wait for each short route update. The summary should read London
   Victoria → Brixton → Herne Hill → Kent House, the selected stations should receive orange map
   markers, and the build investment should add £2m for each station not already in the network.
4. Toggle one call off and on. While the update spinner is visible, the other call rows, Build
   button and railway-class controls should remain disabled until the latest route is ready; no
   stale call or wrong route should win. Switching to High speed should return to endpoint-only
   operation. On a longer route, a 17th call should be disabled with clear limit copy.
5. Build the four-stop conventional line and let construction finish. With the default Balanced
   timetable, the local train should stop briefly at Brixton and Herne Hill while the express train
   passes through. Arrival rewards should appear at an intermediate station when it is visible.
6. Change the service to Local: every train should call at both intermediate stations. Change it
   to Express: every train should run endpoint-to-endpoint without an intermediate dwell. The line
   card should retain all four ordered calling points throughout.
7. Inspect Brixton or Herne Hill and compare Local with Balanced at higher frequency. Intermediate
   platform calls and effective frequency should reflect only trains that actually stop, while
   both endpoints retain the full timetable. Passenger access, happiness, revenue and station
   upkeep should update for the real intermediate journeys.
8. In a fresh game, build London Victoria–Kent House directly. Open a train card, choose **Edit
   stops**, and tap Add beside Brixton. The confirmation should name Brixton, show the exact cost,
   and explain that the call is permanent. Cancel once to confirm that nothing changes, then add
   it: Career mode should charge only Brixton's station cost, preserve the existing track, line and
   trains, and show Brixton in the ordered call list. An unaffordable Add button should be disabled
   without changing cash or the route.
9. Force-quit and relaunch. The selected calls, route, train positions, cash and lifetime capital
   spend should restore exactly; Edit stops should offer only remaining eligible stations.
10. Repeat the preview and Edit stops panels on a narrow portrait iPhone, at an Accessibility text
    size, in Light and Dark Mode, with VoiceOver and Reduce Motion. Rows should scroll without
    clipping, announce selected order and prices, and leave the visible map available to pan and
    zoom.

## Testing Milestone 15 manually

1. Install this build over the tested Milestone 14 build without deleting the app. Open the saved
   railway and confirm every existing service remains a one-corridor service with unchanged line
   number, colour, calls, trains, finances, station progress and operating-day position. No
   migration purchase or cash movement should occur.
2. Start a fresh Career game. Build **Purley–East Croydon** first and **East Croydon–Horley**
   second as completed conventional services. Make the first service half-hourly, Balanced and
   eight-car; make the second hourly, Local and six-car. Leave both on single track. Arrange a loan
   before either build if its preview reports a funding shortfall.
3. Pause the game once both services are complete. Record the cash balance, gross network value,
   lifetime construction spend, lifetime rolling-stock spend, each service's line number and
   colour, and the number of trainsets each service owns. The paused values are the exact pre-merge
   baseline for the finance and asset checks below.
4. Open the first service's controls and choose **Join service**. Select the East Croydon–Horley
   service. The preview should show Purley → East Croydon → Horley, list East Croydon only once,
   identify the first service as the primary service, explain that the second service will be
   removed, and show that its corridor and purchased trains will be retained. The pair must be
   actionable rather than blocked. The review sheet should say that the joined service will use
   the first service's half-hourly Balanced timetable and should itemise extending the second
   service's owned trainsets from six to eight cars at the normal rolling-stock price. It must not
   quote track or station work in this example.
5. Cancel the review once. Both original services, their trains, finance values
   and network value must remain unchanged. Reopen the join control and confirm the automatic-change
   list and total are identical. If the Career balance is below that total, the confirmation must
   name the shortfall, prevent the join and leave the whole network unchanged until enough funding
   is available.
6. Confirm the merge. **Your lines** should now contain one Purley–Horley service rather than the
   two original services. It should retain the first service's line number, colour, operating
   frequency, stopping pattern and active train identities, use eight-car trains throughout, show
   two retained corridors and three ordered calling points, and show the second service's purchased
   trainsets as owned spares. The second service should no longer appear independently.
7. Recheck the paused Career figures. Cash should decrease by exactly the quoted upgrade total and
   lifetime rolling-stock spend and gross network value should rise by the same amount. Lifetime
   construction spend, station assets and loan balances must otherwise remain unchanged. The join
   must create no unquoted finance transaction.
8. Resume at 3× and watch each active train complete the full Purley–East Croydon–Horley route in
   both directions. The route should render continuously in the primary service's colour, trains
   should call at East Croydon according to the retained service pattern, and direct Purley–Horley
   demand should replace the former forced change there. Passenger, capacity, happiness and
   operating forecasts should recalculate for the through service.
9. Build a completed **Horley–Redhill** conventional service. Reopen the Purley–Horley through
   service: its card should now say **Extend service** and offer a Purley–Redhill result. Review and
   confirm it. The primary number, colour and active trains should survive, all three corridor
   identities and paid trainsets should remain owned, and the new ordered calls should be Purley →
   East Croydon → Horley → Redhill. **Edit stops** and single-corridor track upgrades remain
   unavailable, while service and formation controls continue to apply to the complete route.
10. Force-quit and relaunch. The Purley–Redhill service, primary number and colour, ordered calls,
    formation, three corridor identities, active and spare trains, train positions, finance values,
    network value and derived passenger connections should restore without a duplicate purchase or
    topology error. Let trains run again to confirm that every corridor leg remains traversable
    after cold restore. In a separate exact-match pair, verify that the same flow quotes no automatic
    investment and leaves cash and network value unchanged.
11. Repeat the join preview and confirmation on a narrow portrait iPhone, at an Accessibility text
    size, in Light and Dark Mode, with VoiceOver, Reduce Motion and Differentiate Without Color.
    The candidate and consequence copy should scroll without clipping, announce both old services
    and the new ordered route, and leave the unobscured map available to pan and zoom.

## Testing Milestone 16 manually

1. Install this build over the tested Milestone 15 build without deleting the app. Open the saved
   railway and confirm its lines, calls, trains, positions, finances and operating-day progress are
   unchanged. Existing Local, Balanced and Express services should receive matching default plans
   without a purchase or cash movement.
2. In Zen mode, build a completed conventional **London Victoria–Kent House** service calling at
   both **Brixton** and **Herne Hill**. Tap one of its trains. The train card should show its train
   number, Local or Express role, two terminals, call count and an **Edit plan** button.
3. Open **Edit plan** for Train 1. Choose London Victoria and Herne Hill as its terminals and set it
   to Local. The calling-point list should automatically include Brixton and should not offer a way
   to skip it. Save, run at 3×, and confirm that this train turns back at Herne Hill and dwells at
   Brixton in both directions rather than continuing to Kent House.
4. Use **Choose another train**, edit Train 2, choose Brixton and Kent House as its terminals, and
   set it to Express. Add or remove Herne Hill as an Express call, save, and watch several trips.
   Both terminals must remain mandatory; the train should pass Herne Hill without dwelling when it
   is omitted and should stop there when it is selected. Its marker must remain aligned with the
   route while turning back at each chosen terminal.
5. Compare the line and station cards before and after changing that Express call. Passenger
   access, effective service, platform calls, crowding, wait time and operating result should
   recalculate immediately from the actual combination of train plans. Editing a plan itself must
   not change cash, capital spend or network value.
6. Raise the service to quarter-hourly, use **Choose another train** to give Trains 3 and 4 distinct
   plans, then reduce the service to hourly and raise it again. The saved Train 3 and Train 4 plans
   should return with the reactivated timetable slots; no plan should migrate to the wrong train.
7. With custom plans active, choose a Local, Balanced or Express fleet preset. The game should ask
   before replacing all four plans. Cancel once and confirm that every custom plan remains, then
   apply the preset and confirm that all trains receive its expected default calls. The explicit
   **Reset every train** button should provide the same protected reset for the current preset.
8. Build and join **Purley–East Croydon** and **East Croydon–Horley**. On the resulting through
   service, give one train Purley–East Croydon Local operation and another East Croydon–Horley
   Express operation. Both should be editable and should use the retained shared infrastructure;
   the outer Purley–Horley journey should now require a change at East Croydon unless another train
   directly calls at both outer stations.
9. Force-quit and relaunch with several custom plans active. Every role, terminal, intermediate
   call and dormant timetable-slot plan should restore. Resume at 3× and verify trains remain
   inside their own terminal bounds with no duplicate purchase, settlement or service.
10. Repeat the train summary, editor, train chooser and preset confirmation on a narrow portrait
    iPhone, at an Accessibility text size, in Light and Dark Mode, with VoiceOver and Reduce
    Motion. The panel should use one bounded scroll area, every control should remain reachable,
    and all unobscured parts of the map above and below it should continue to pan and zoom.

## Testing Milestone 17 manually

1. Install this build over the tested Milestone 16 build without deleting the app. Open the saved
   railway and confirm its corridors, services, custom train plans, finance, population and train
   positions restore. An untouched long Local or Balanced preset may adopt the new bounded
   regional plan; a player-customised plan must remain unchanged. The new Local limit applies only
   when saving a new edit.
2. Start a Zen game and choose **Build a line**. On both the origin and destination steps, tap
   **Find station**. Search once by name and once by CRS: for example **Aberdeen / ABD**,
   **Edinburgh / EDB**, **Penzance / PNZ**, **Cardiff Central / CDF** and **Swansea / SWA**. Exact
   CRS matches should appear first, selecting an offscreen origin should move the map to it, and
   the chosen station must advance the normal build flow. Cancel and reopen the search to confirm
   that cancelling changes nothing.
3. Build a short non-South-East route such as Cardiff Central–Swansea. Its preview must follow the
   bundled railway rather than a straight line, list eligible intermediate stations in route
   order, complete construction, animate trains and survive a force-quit/relaunch exactly like the
   original London routes.
4. Preview a national route from **London Kings Cross (KGX)** to **Edinburgh (EDB)**. Confirm that
   the first request can take a moment while the local railway graph loads, then pan and zoom the
   preview. The line must stay responsive and retain its endpoints. An endpoint-only Local or
   Balanced choice is allowed to become Express rather than labelling an implausible 600 km
   all-stop train as Local.
5. For a dense Local test, build **London Victoria–Brighton** and use **Calling points → Edit
   stops** in the preview to add the available intermediate stations, including Clapham Junction,
   East Croydon, Purley, Gatwick Airport and Haywards Heath. Complete construction and select the
   Local preset. Open each active train: its Local terminals should describe bounded regional
   workings, every selected station should have service, adjacent regions should share a station
   where passengers can change, and no Local train should traverse the entire line when the
   distance, time or call-count limit would be exceeded.
6. Change that service to Balanced. Local trains should retain regional terminals while Express
   trains run between London Victoria and Brighton and skip the minor calls. Passenger access,
   platform throughput, crowding and forecasts should update from both the regional and full-route
   workings, even though the map deliberately shows only the four timetable representatives.
7. Open **Edit plan** on a train and try to make the full dense route Local. The editor should
   explain that it is too long and keep **Save plan** unavailable. Change the same train to Express,
   keep the two outer terminals, optionally choose intermediate calls, and save. It should now run
   the complete route. This is also the intended path for a deliberately exceptional national
   service such as Aberdeen–Penzance.
8. Zoom out to a Great Britain view, then pan repeatedly between Scotland, Wales and southern
   England while trains run at 3×. Candidate station markers, train markers and route detail should
   reduce at wider zooms and return progressively when zooming in. Gestures must remain responsive;
   searched, selected and nearby built stations must not disappear, and the line directory must
   still frame a chosen offscreen service.
9. Build several routes in different regions, including more than the old 12-service limit if
   practical. Confirm line colours, directories, searches, passenger totals and saving continue to
   work. The corruption-safety ceilings support 512 services and 256 calls per service; the UI must
   refuse the next edit cleanly rather than losing an existing route.
10. Leave a multi-region network running at 3× for at least ten minutes on a physical iPhone with
    world effects first off and then on. Pan only intermittently. Check that train motion remains
    smooth, controls stay responsive and temperature stabilises rather than continually rising.
    In Xcode's Debug navigator, record any sustained CPU, memory or Energy Impact increase so the
    same network can be used as a repeatable performance baseline.
11. As a coverage-boundary check, a mainland-to-Isle-of-Wight build should report that no mainline
    route is available, while two Island Line stations should route together. This is expected
    graph topology, not a search failure. Northern Ireland is not yet present in the bundled Great
    Britain data.
12. Repeat the finder, long preview, train-plan warning and country map at an Accessibility text
    size, in Light and Dark Mode, with VoiceOver and Reduce Motion. Search results and controls must
    remain labelled and reachable, and unobscured map areas must continue to pan and zoom.

## Testing chained service extensions manually

1. In Zen mode, build three completed conventional services in order: **Purley–East Croydon**,
   **East Croydon–Horley**, and **Horley–Redhill**.
2. Join the first two services. Open the resulting Purley–Horley service and confirm the former
   dead-end message has been replaced by **Extend service**, offering the Horley–Redhill line.
3. Open the proposal. It should show Purley → East Croydon → Horley → Redhill, three retained
   corridors, all automatic timetable/fleet/track changes, and the exact total investment. Cancel
   once and verify that no service, corridor, train or finance value changes.
4. Confirm the extension. One Purley–Redhill service should remain, using the selected primary
   line's number, colour, frequency and active train identities. All purchased trainsets should
   remain owned, with absorbed trains shown as spares, and trains should traverse all three legs.
5. Repeat from the opposite end by adding a completed service at Purley. The proposal and result
   should orient the entire existing chain correctly rather than reversing only its first segment.
6. Give one source longer trains and stronger track before joining. The review must list every
   weaker named corridor segment and fleet extension once. In Career mode, compare the quoted
   total with the cash and lifetime capital changes after confirmation; they must match exactly.
7. Test the same paid proposal without enough Career cash. **Review funding** should show the
   shortfall and offer **Open Network finances**. Neither closing the review nor attempting the
   unaffordable join may alter the railway or ledger.
8. Customise the primary service's train plans before an extension. The review should explain that
   those terminals and calls will be retained; after joining they should remain exact short-running
   plans until edited. With untouched presets, Local/Balanced/Express defaults should instead
   expand across the complete new route.
9. Force-quit and relaunch a three- or four-corridor result. Corridor order, calls, custom plans,
   active and spare trains, positions and finances should restore exactly. Also confirm that
   disconnected, overlapping, branching, looping or mixed conventional/high-speed pairs remain
   blocked as topology issues rather than being presented as purchasable fixes.

## Testing connected station selection and map responsiveness manually

1. Open an existing multi-line save, choose **Build a line**, and wait for the brief **Checking
   railway connections** state. Valid origins should become bright/selectable; isolated catalogue
   entries with no other station in their railway component remain grey and cannot be selected.
2. Select a mainland origin, then pan to the Isle of Wight. Island Line stations should be grey
   and non-selectable because there is no OSM railway path from the mainland. Open **Find station**
   and search for the same station: it must not appear. Cancel, start on the Island Line instead,
   and confirm another Island Line station is offered while mainland destinations are not.
3. Start at **East Croydon**. **West Croydon** must remain grey, reject taps, and be absent from
   **Find station**: although both stations belong to the mainland graph, the only graph route is
   an implausible indirect loop rather than a direct corridor. **Selhurst** and **Purley** must
   remain selectable. Repeat in reverse from West Croydon and confirm East Croydon is excluded.
4. As a regression for legitimate indirect geometry, confirm **Manchester Piccadilly–Manchester
   Victoria** remains selectable. **London King's Cross–St Pancras International** should be
   excluded because its graph route is an indirect loop rather than the adjacent road distance.
5. Start from one end of an already-built direct service. Its other endpoint must be grey and
   absent from **Find station**, preventing a duplicate service before route calculation begins.
6. At country and regional zoom, tap slightly beside a valid marker rather than directly on its
   centre. Build candidates accept taps across a 64–72 point diameter and built stations across a
   52–60 point diameter; the visible marker itself should remain compact.
7. Where two station targets overlap, tap nearer each marker in turn and confirm the closest one
   wins. Drag starting beside or over a marker and pinch to zoom: the map gesture must win once the
   finger moves. If a train is dwelling over a station, tapping the train should still open its
   controls rather than the station panel.
8. With several lines operating at 3×, pan continuously around London, then zoom out and pan from
   southern England to Scotland and back. Map movement should remain responsive, train movement
   should resume normally when the gesture ends, and there must be no catch-up jump after a long
   drag. Route detail may simplify progressively at regional/country scale and return when zoomed
   in.
9. Repeat step 8 for at least ten minutes on a physical iPhone. Compare the same save with the
   previous build using Xcode's Debug navigator. Check sustained CPU, memory and Energy Impact,
   and confirm device temperature stabilises rather than continuing to rise.
10. With VoiceOver enabled, swipe to a station marker and activate it. Its station name, status and
   action should remain available even though the redundant transparent annotation layer has been
   removed.

## Testing map station insertion and the thermal pass manually

1. Use a completed single-corridor conventional service such as **East Croydon–Purley**. Zoom to
   local or regional scale around **South Croydon**. Its marker should have a green **+** and name;
   tapping slightly beside it should work without requiring maximum zoom.
2. Tap South Croydon. A review should briefly say that it is checking the railway path, then show
   **East Croydon → South Croydon → Purley**, the affected Local/Balanced/Express behavior and the
   exact station cost. Cancel first and confirm that the line, cash and station count do not change.
3. Open the review again and confirm the purchase. South Croydon should become a built station in
   the correct route order; Local trains should call, Balanced express trains should pass, and an
   Express-only service should retain its current calls until edited. Force-quit and relaunch to
   confirm the station, service plans, finances and train identities restore correctly.
4. Try a station visibly away from the railway and a station near an ineligible high-speed,
   constructing, full or merged service. It should not receive the **+** affordance. If the cheap
   map preflight finds a marginal candidate that the authoritative OSM anchor rejects, the review
   must explain that it cannot be added and leave the railway unchanged.
5. For the thermal comparison, let the phone cool, use the same saved network and run an Xcode
   **Release/Profile** build for five minutes at 1× with world effects off. Repeat at 3×, then with
   world effects on in clear weather and rain/fog. Keep the map mostly still and note Xcode's CPU,
   Energy Impact and the phone's temperature. Pausing must bring continuous simulation work close
   to idle; panning and pinching must remain responsive with no catch-up jump on resume.
6. Repeat step 5 at country and local zoom. The train presentation now runs at an energy-conscious
   10 updates per second, inactive/paused display links stop completely, static HUD figures no
   longer subscribe to train movement, and weather redraws are capped separately. Train movement
   should remain clear while sustained heat and CPU activity are materially lower than the prior
   build.

## Persistence

The game maintains one versioned local save in Application Support. Schema 12 separates durable
physical railway corridors from the train services operating over them. Corridors store ordered
station CRS codes, construction progress, railway class and track capacity; services store stable
identities, ordered corridor references and calling points, timetable, formation, fleet, train
progress and four stable per-slot stopping plans. Each plan stores its Local or Express role and
ordered calls, including its independently selected terminals. Geometry and current construction
prices remain derived from the bundled graph.

Schema 12 also stores game mode, Career cash, loans, lifetime capital and financing totals,
insolvency state, station evolution and synthetic population, plus the bounded 120-day Statistics
history. Schemas 1–11 migrate deterministically: every historical line becomes one retained
corridor and one two-stop service using the historical line ID. Schemas 2–11 preserve their exact
operations, fleet, train positions, economy, finance and capital history. Schema 1 predates service
frequency and purchased-fleet fields, so it adopts the established half-hourly two-train baseline
while retaining its saved train and all available financial state. Migration records no purchase
and never retroactively charges for track or rolling stock.

The schema-12 save store validates complete, connected corridor references, correctly ordered
service calls and exactly four valid stopping-plan slots rather than silently inventing topology.
Schema 11 plans are synthesised from the saved fleet preset: Local trains receive every existing
call, Express trains receive the outer endpoints, and Balanced alternates those defaults. Milestone
14 creates and restores real
ordered calls on each service and the corresponding ordered stations on its retained corridor.
Milestone 15 can repeatedly replace two compatible services with one service that stores every
retained corridor identity in traversal order. Either source can already be a through service. The
primary service identity and active trains survive, the secondary fleet remains owned as spares,
and restore resolves each physical corridor before reconstructing the complete through route. An
exact-match merge adds no purchase record; when automatic asset reconciliation is required, only
the itemised per-corridor and fleet upgrade quote is recorded once as normal capital spending.
Milestone 16 preserves inactive stopping-plan slots across frequency
changes and restores every plan before safely placing its active train inside the selected terminal
bounds. Milestone 17 keeps schema 12: on restore, only an exact untouched historical preset is
regenerated into the new bounded regional defaults; any player-authored train plan is preserved.
Logical regional runs, map level of detail and catalogue search are derived state and add no save
payload. Restore never repeats a purchase. Migrations and stopping-plan edits remain free, while
prestige and passenger projections remain derived rather than duplicated.

Network changes, purchases, borrowing, repayments, and completed operating days are saved shortly
after they happen. Moving-train progress is checkpointed periodically, and the latest state is
flushed when the app leaves the foreground. A restored line is routed again over the current
bundled graph rather than persisting stale map geometry. Network value, accessibility, and
happiness are deterministic projections of durable state, so they are recomputed on launch rather
than duplicated in the save file. Connecting-passenger demand is likewise derived from the restored
operating lines and is not stored separately. Platform throughput, effective service frequency,
limiting stations, and bottleneck warnings are also deterministic projections of saved line
timetables and station levels, so they remain outside the save payload.

If a save cannot be read or restored, the launch screen offers retry and a confirmed option to delete it and start fresh.

## Known POC limitation

Station catalogue coordinates and the nearest OSM railway-routing anchors do not always coincide exactly, so a line can appear slightly offset from its station marker at close zoom. This is accepted for the current proof of concept.

New-line choices use the bundled OSM graph's physical geometry as a conservative proxy for a
plausible direct corridor. The graph does not contain a complete passenger timetable or every
operational turn restriction, so unusual real-world through services may still need future routing
metadata. Existing saves are not destructively pruned if a historical line fails this newer build
rule; its route is reconstructed from trustworthy station anchors instead.

The durable model separates physical corridors from services and retains ordered physical
stations independently from a service's ordered calls. Intermediate stations can be selected at
build time or added permanently to a completed single-corridor conventional service, but they
cannot yet be removed or reordered. New infrastructure supports up to 256 calls per service and
the train-plan editor can use that same bound for a deliberately long Express working; automatic
Local zones use at most 12. The save format uses a 512-service/1,024-corridor corruption-safety
ceiling rather than the earlier gameplay-sized limit. High-speed services remain endpoint-only,
cannot be merged and do not support custom stopping plans.

The bundled catalogue and railway graph cover 2,606 stations in Great Britain. Northern Ireland is
not included in the existing TrainTrack UK catalogue/graph and needs a separate future data import.
The Isle of Wight is a valid isolated railway component: routes within it work, while a direct
mainland connection correctly remains unavailable. At country zoom the map deliberately culls
stations and simplifies route overlays under strict scale-dependent budgets rather than drawing every
built station, unbuilt station and service at full local detail simultaneously; **Find station**
is the authoritative way to select any catalogue station that has a valid OSM railway path for
the current builder step. Route geometry and track decoration return progressively as the player
zooms in.

A through service can be extended through repeated destructive merges of completed conventional
services that share exactly one outer terminal and form one continuous, non-repeating corridor
chain. Frequency, formation and track-capacity differences are presented as an itemised automatic
reconciliation rather than blocking the merge. Budget can resolve those operating and asset
differences, but it cannot make disconnected lines, overlapping routes, branches, loops or mixed
conventional/high-speed infrastructure into one unambiguous linear service. Joined services cannot
edit their physical stops or upgrade only one part of their track; those controls remain available
to eligible single-corridor services. Active trains can use independent custom terminals and Local
or Express calls across the stations already present on the joined route.

Custom stopping plans reorganise service only over stations that are already part of the line.
They do not discover or construct a new physical station; that remains a separate build-time or
single-corridor **Edit stops** action. Only active trains can be selected directly, although all
four stable timetable slots retain their plans while dormant. Plans currently share the line's
single purchased formation and fixed one-departure-per-hour slot model; the POC does not yet offer
per-plan frequencies, clock-face departure times, service names or individual rolling stock.
Automatic regional Local workings are deterministic planning abstractions based on selected calls,
distance and estimated running time; they are not imported real-world timetables. Adjacent zones
share a transfer station and the passenger/capacity models account for every zone, while only four
representative train markers remain animated. The POC does not yet calculate depot allocation,
crew diagrams or the extra physical fleet required to reproduce every logical departure exactly.

Station capacity is an aggregate call forecast: each platform supplies four train calls per hour,
and overloaded endpoint or intermediate calls share that capacity proportionally. The POC does
not yet assign a specific train to a platform, animate platform queues or cancellations, model
turnback time, or apply platform-length and signalling constraints. Scheduled trains remain
visible while the cards show the lower effective passenger service produced by a bottleneck.

Connecting demand supports any number of active endpoint services but remains limited to one
interchange per passenger market. A direct service takes priority; otherwise one deterministic
best transfer itinerary is used rather than splitting demand across alternatives. The POC does not
yet allow multiple changes, coordinate timetables, or model missed connections and individual
passenger itineraries. Compact interchanges evaluate every possible outer pair; an exceptional hub
with more than 2,048 possible pairs keeps the best 2,048 by journey quality. Likewise, national
happiness retains exact connectivity and destination-importance coverage while its detailed
journey-time, frequency, reliability and crowding scores use a deterministic 128-destination sample
per station. These explicit budgets keep operating-day recalculation practical on an iPhone.

Every line currently uses one uniform formation across all of its active and spare trainsets.
Fleet extensions are permanent and fleet-wide: this POC does not yet shorten, sell, transfer, or
individually configure trains outside the automatic absorption of a compatible secondary fleet
during a through-service merge. It also does not distinguish seating layouts or rolling-stock
families, or model depot, platform-length, axle-load, electrification, and clearance restrictions.

Settlement populations are synthetic catchment figures chosen for gameplay balance, not official
population estimates for the named place or local authority. They currently grow only from rail
accessibility and local happiness; housing capacity, jobs, tourism, land use, migration, decline,
and real demographic datasets are outside this POC.

High-speed rail is currently chosen only when previewing a new line; conventional lines cannot be
retrofitted. It follows the same existing OpenStreetMap-derived route geometry, with no new
alignment design, corridor eligibility rules, or research progression. The one-service-per-pair
rule prevents parallel conventional and high-speed services between the same two stations, and
high-speed lines are fixed to Express-only operation on double track.

## Open in Xcode

Open `TrainTrackTycoon.xcodeproj`, choose an iPhone simulator running iOS 18.6 or later, and run the `TrainTrackTycoon` scheme.

## Data

The Apple MapKit basemap is online. The station catalogue is reused from TrainTrack UK with the author and owner's approval for this project. Railway routing geometry is bundled locally from OpenStreetMap-derived data. See `DATA_LICENSES.md` for attribution and licence information.
