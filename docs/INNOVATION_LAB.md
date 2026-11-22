# Innovation Lab MVP

The Lab runs in its own server session in a flat 150 × 150 stud room. Its four walls enclose the floor, and the roof is open for the tank camera. There are no practice targets or obstacles. The Lab reuses the authoritative tank, projectile, BW, and possession systems.

## Enter and run an experiment

- In the published Playground, open **Main Menu → Innovation Lab**. This opens a private Lab session. **Return to Playground** in the catalog sends you back to a public server. It may be a different Playground server from the one you left.
- To run the room locally in Studio, set `ServerStorage → BattleWorksStudio → GameMode` to `InnovationLab` in Edit mode and start Play. To return locally, stop Play and start again with `BattleRoyale`.
- **Retaliator Mesh** is the available card. Viper Sensor, Dog Ears, Echo Radio, Echo-EMC, Echo Sensor, and Thread Dispatchers are visible placeholders.
- Select Retaliator Mesh to spawn a tracked Boomer with 25% power assigned to the Mesh, facing a wheeled Crazy with a Gatling. Crazy uses the existing packaged Playground source and bus policy. A surviving hit wakes the Boomer's event handler, which prints the hit and tries to turn and drive away. The demonstration is built from `programs/examples/retaliator-mesh.bw`. Run `node tools/build-bw-personalities.js --lab` after editing it.

## Possession and restart

Approach either tank and press **E**, controller **X**, or the touch prompt. Entry switches the occupied tank to Manual and stops its autonomous invocation. Choose **Auto** from the tank HUD to restart the last program you ran from the BW Editor during this possession, or the built-in program if you have not run an edit. Press **F**, controller **B**, or the exit button to get out and let the vacated tank return to Auto. You can then approach and enter the other tank.

Select **Tech Catalog** to end the experiment and discard the tanks, their projectiles, and their running BW state. Select the same card again for a fresh experiment. The Lab carries no experiment tanks, scores, or equipment into the Playground. Lab equipment is preset. The Playground Garage rejects Retaliator Mesh configurations.

The offline suites cover entry, live projectile-to-Mesh dispatch, possession of both tanks, catalog exit, repeated resets, stale lease protection, and mocked teleport routing. Native teleport matchmaking, render and control behavior, and heap usage over long Studio reset sessions still need live verification.
