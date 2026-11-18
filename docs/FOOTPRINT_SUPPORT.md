# Structural ground support

The seam bug was in Environment.pose, not native Roblox raycasting. It queried five points (center and four axial points) through WorldObjects:support. Intersecting narrow gaps could miss all five although most of the chassis stood over solid geometry. Its reference-plane fallback could conversely extrapolate a single supported point beyond a cliff. WorldObjects' compound mesh colliders made this insufficient sampling more noticeable.

WorldObjects:footprintSupport now passes live solid top-face geometry to shared FootprintSupport.solve. It uses the chassis ContactWidth/ContactLength (the existing suspension footprint), rotated by authoritative yaw. It clips every nearby walkable top-face polygon against that footprint. Builtins, imported models and fitted compound cells use the same geometry path.

The contact polygons must surround the chassis center in their convex support hull. A seam can lie under the center without losing support if actual faces still support the body on either side. One-sided contact past a cliff, a grazing corner or a gap wider than the chassis cannot suspend it. There is no world-space gap-closing distance and no added collider. A very narrow board remains usable when the chassis is centered on it.

An area-weighted suspension plane fits the real contacts, preserving exact planar ramp pitch/roll and blending neighboring surfaces. Its height clears the contact vertices. Existing maximum walkable angle and 1.5-stud step rules remain; lower levels outside the reachable top contact band cannot prop up a tank on an upper deck. Ramp contact levels are bounded by their actual clipped contact heights, avoiding extrapolating a ramp past its end and discarding the adjacent platform. This is the existing scripted suspension model, not a new dynamic tipping solver.

Environment retains procedural terrain sampling and uses whichever is higher: procedural ground or valid structural support. TankSimulation's normal movement and post-contact reconciliation both consume this same pose. VehicleContacts side collision/CCD, pushing, recoil/gravity, projectile-ground queries, serialization and the world format are unchanged. Destroyed and non-solid cells never provide structural support.

Regression coverage is in tests/FootprintSupport.spec.luau (runner group 40): center and cross-shaped seams, yaw, stationary and driving tanks, slightly uneven neighbors, rotated compound cells, destruction, flat/ramp joins, large gaps, partial cliff support and overhead rejection. Existing WorldElevation group 32 covers 30/40/45-degree narrow boards, elevated bridges, travel beneath decks and multilevel projectile behavior. Broader physics suites cover pushing, recoil and contacts.

Native Studio checks after Rojo sync (no place build needed):

1. Drive both tank types over perpendicular and diagonal seams, including seams directly beneath the tank center. Try 0.05–0.25 stud gaps and neighboring tops differing by 0.4 studs.
2. Cross a flat-to-ramp join and the same join onto a raised platform. Rotate the whole layout and repeat. Tanks should retain height without a nose dive or side snag.
3. Repeat on adjacent solid Kenney rock compound cells. Confirm destroying an object removes its support immediately.
4. Drive slowly and push another tank toward an exposed edge. Support should release once its center moves beyond the real supporting footprint. Cross a hole wider than ContactWidth/ContactLength to confirm it falls normally. Confirm tanks below a bridge do not jump onto its deck.

Native presentation and the imported mesh-to-cell fit still need Studio validation; the footprint algorithm itself uses the authoritative collider geometry and requires no client hit claims or native raycasts.
