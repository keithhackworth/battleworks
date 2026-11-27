# BattleWorks — Tank Ownership and Persistence Specification

**Status:** Design baseline for source reconciliation and phased implementation  
**Scope:** Ownership, starter assignment, Motor Pool, Training Grounds, programs, presets, and deployment validation.

## 1. Implementation contract

This specification defines intended behavior, not a claim about the current implementation. Before changing code, reconcile it against the repository, identify existing services, data stores, catalog IDs, Bunny compiler/runtime capabilities, configuration controls, and deployment paths. Report conflicts, missing capabilities, migration needs, and unresolved decisions for approval. Do not silently change gameplay or invent equipment rules. Once approved, reference this specification from AGENTS.md and keep it authoritative. Preserve existing functionality outside the scope of this effort.

## 2. Core model

Separate persistent ownership from runtime operation:

- **Player:** owns tanks, individual equipment instances, and reusable Bunny programs; has a permanent starter-assignment entitlement state and appearance defaults.
- **Owned tank:** permanent unique ID, owner, editable display name, hardware configuration, selected program, bus configuration, tank-specific presets, and extensible appearance/settings.
- **Equipment catalog:** stable type IDs and definitions of capabilities, compatibility and constraints.
- **Equipment instance:** individually owned physical item with a unique ID and catalog type ID. Owning one item does not unlock unlimited copies.
- **Program:** reusable player-owned Bunny source with stable ID and validated compatibility requirements.
- **Preset:** tank-specific partial or complete configuration description, not an ownership entitlement.
- **Deployment:** validated snapshot of selected tanks, equipment allocations, programs and settings for a round.
- **Runtime tank:** live simulation instance; its current operator may differ from its owner.

Names are never identifiers. Players may rename their own tanks at any time; apply Roblox-required text filtering to user-visible names. Renaming must not affect references or an active round's configuration.

## 3. Persistent storage

Use Roblox DataStore-compatible nested Luau tables (document-style key/value storage). One-to-many relationships can be represented by arrays or dictionaries of records. Do not serialize runtime Instances, functions, or Roblox-specific values directly; encode colors and other values using supported primitives. Prefer atomic updates of closely related ownership data within a player record where practical; assess entry size, write budgets, and existing storage architecture before choosing the final partitioning.

Illustrative logical schema (field names are provisional and must be reconciled with source):

```json
{
  "schemaVersion": 1,
  "playerId": "player-id",
  "starterAssignment": {"accepted": true, "tankId": "tank-1"},
  "appearanceDefaults": {"primary": [80,100,65], "secondary": [40,50,35], "accent": [200,160,50]},
  "equipmentInventory": {
    "eq-1": {"catalogId": "retaliator-mesh"}
  },
  "programLibrary": {
    "program-1": {"name": "Retaliator", "source": "...", "revision": 1, "requirements": {}}
  },
  "tanks": {
    "tank-1": {
      "name": "Merlin",
      "hardware": {"chassisId": "catalog-id", "drivetrainId": "catalog-id", "weaponId": "catalog-id", "devices": [{"equipmentInstanceId": "eq-1", "slotId": "slot-1"}]},
      "software": {"programId": "program-1"},
      "configuration": {"busAllocation": {}},
      "appearance": {"colorOverrides": {}, "effects": {}},
      "presets": {},
      "revision": 1
    }
  }
}
```

This example does not imply actual catalog IDs, slot semantics, or bus layout. Account for individually owned chassis, weapons, drivetrains and other limited hardware wherever applicable; the example's catalog references do not authorize free duplication. Establish a consistent ownership representation for starter equipment during source reconciliation.

Persist identity, ownership, starter entitlement, hardware, program references/source, current saved bus configuration, presets, and extensible settings. Support three colors (primary, secondary, accent), with proposed player defaults and optional per-tank overrides. Reserve extensible settings for future track trail and kill-shot effects; do not implement those effects now.

Do not persist current health, position, orientation, cooldowns, event queues, CPU execution state or other transient simulation state as part of tank ownership.

### 3.1 Reliability

- Server-authoritative validation and writes; never trust client ownership or compatibility assertions.
- Versioned schemas and explicit migrations; preserve existing player data.
- Atomic, idempotent starter assignment and exchange operations, including transaction IDs and verification after ambiguous write failures.
- Prevent stale or concurrent sessions from overwriting newer data; use revision checks/session coordination appropriate to the existing architecture.
- Never treat a failed load as an empty inventory or overwrite existing data with defaults.
- Report save failures, allow safe retries, and preserve unsaved edits where practical. Do not report successful assignment until persistence is confirmed.
- Respect DataStore limits and throttling; avoid writes for runtime simulation ticks.

## 4. Initial Tank Assignment

### 4.1 Unassigned Recruit

A player who has never accepted their starter assignment enters Training Grounds on foot, without a tank. They can enter available training tanks, drive, fight, program, configure the bus, and experiment with drivetrain and weapon choices in existing blue configuration bays. They can exit and try another tank freely.

Add **Accept Tank Assignment** to the existing blue configuration popup for eligible Recruits only. Use accessible military language, not “Claim Tank” or “Requisition.” Address the player as **Recruit**, not Commander; no dynamic rank lookup is needed for this one-time event.

Suggested copy:

> **YOUR FIRST TANK**  
> Listen up, Recruit! You are authorized one starter tank. Test your equipment and choose carefully. This is a one-time assignment. Once accepted, your drivetrain and weapon can only be changed through upgrades.

Show a confirmation with the actual selected drivetrain and weapon and the one-time restriction. Allow cancellation without side effects. On confirmation, validate eligibility, current operator, valid blue bay, source tank eligibility, equipment and bus configuration. Atomically create the owned tank and consume the starter entitlement. Preserve the selected valid configuration and program subject to the source eligibility rules below. Transition seamlessly to the owned tank without forcing the player to leave Training Grounds.

Success message: **ASSIGNMENT CONFIRMED** — Congratulations, Recruit! Your first tank has been assigned to you and added to your Motor Pool. Report to the Motor Pool for your next orders.

Hide the assignment action permanently after successful assignment. Rejoining, changing servers, destruction, deletion, or character reset must not restore entitlement.

### 4.2 Assignment from another player's tank

An owned tank may serve as the source of an initial assignment only if it is a default starter tank with no upgrades and standard BW code. Validate against authoritative catalog and standard-program definitions, not client labels. Proposed implementation: create an equivalent starter tank for the Recruit without transferring or duplicating the original owner's limited inventory; the new items are issued under the Recruit's one-time entitlement. The original owner retains their tank. Confirm exact default-code and starter-eligibility definitions during reconciliation.

### 4.3 Starter exchange

Provide a recovery path for players who regret their initial drivetrain or weapon choice, rather than encouraging them to quit. Proposed action: **Exchange Starter Tank**, in Training Grounds. It replaces starter hardware without granting another tank or resetting the original entitlement.

Proposed eligibility pending explicit approval: original starter tank, no equipment upgrade history, no additional owned tanks; unlimited exchanges while eligible. Colors, bus changes and program edits do not count as upgrades. Retain tank ID, name and appearance; revalidate programs and presets. No refunds, currency rewards, duplicated equipment or free upgraded items. Perform atomically and disallow exchange while the tank is in an incompatible active deployment or occupied by another player. Confirm exchange frequency, eligibility and handling of incompatible defaults before implementation. The one-time assignment warning remains accurate: exchange is a separate recovery operation, not another free assignment.

## 5. Training Grounds lifecycle

After assignment, every entry to Training Grounds presents a tank selection screen from the player's Motor Pool. Preselect the sole tank when only one exists; the player confirms deployment. Spawn the player already seated in the selected owned tank with its validated configuration.

Players may exit their own tank, enter other available training or owned tanks, and return to their own tank when it is unoccupied. Owned tanks remain in the world when exited. Use tank colors to help players recognize their vehicles; an additional ownership indicator is optional and not a requirement.

| Capability | Temporary training tank | Owned tank |
|---|---|---|
| Drive, fight, test Bunny programs | Yes | Yes |
| Configure bus allocation | Yes | Yes |
| Freely change drivetrain or weapon in blue bay | Yes | No |
| Initial assignment | Eligible Recruit only | Only eligible default source, as above |
| Persistent ownership | No | Yes |
| Authorized hardware upgrades | No | Future upgrade workflow |

Keep the blue configuration popup available for owned tanks. Show drivetrain and weapon as locked/read-only with an upgrade explanation. Bus allocation remains editable. Do not allow blue bays or presets to bypass hardware ownership or upgrade restrictions.

### 5.1 Borrowing

Anyone may enter an unoccupied tank in Training Grounds, including another player's advanced owned tank. The owner cannot forcibly reclaim the seat; they must wait for the borrower to exit. Operator identity never changes ownership.

Borrowers can drive, fire and use installed technology. Proposed policy pending confirmation: allow temporary bus and Bunny program experimentation under normal compatibility rules, restore owner configuration on exit, and never permit borrower changes to persist to the owner's tank, programs, inventory, presets, name or appearance. Borrowers cannot remove or transfer equipment. Initial assignment from a borrowed owned tank is restricted by section 4.2.

Reconcile existing Auto/Manual behavior; proposed behavior is that a tank already in Auto can continue its program while unoccupied. Confirm disconnect, world exit and respawn handling, including when a borrower occupies a tank whose owner leaves. Do not strand players or duplicate owned equipment.

### 5.2 Destruction and rounds

Tanks are never permanently destroyed. Training Grounds tanks respawn at full health. Campaign and challenge tanks destroyed during a round remain unavailable until that round ends. All tanks are restored to 100% health for the next round. No permanent repair cost or damage state. Competition-specific round rules should be reconciled separately; never delete ownership on destruction. Reset transient simulation state on respawn or new round.

## 6. Motor Pool

Provide owned tank inventory, 3D preview using existing assets, rename, installed equipment inspection, three-color customization, program selection/editing, preset management and deployment to Training Grounds. Reuse tank selection components for future Campaign and Competitions where appropriate. Tank names may be changed at any time by their owner; other changes obey configuration and deployment restrictions.

Do not implement buying, selling, trading, scrapping, equipment acquisition or rank progression in this effort. Establish data structures and service boundaries that accommodate those features later.

## 7. Bunny program library and compatibility

Players may own multiple reusable programs. A tank has a selected program attribute. During battle preparation, players can select/drop a compatible program onto a tank. Programs are software, not scarce physical inventory; no one-copy restriction is implied for programs.

Only programs compatible with the specific tank's assembled hardware may be selected for deployment. Requirements include installed devices (e.g. Retaliator Mesh), thread count and any other actual runtime capabilities required by the program. A program requiring Mesh must not be installable on a tank without Mesh even if the player owns one elsewhere.

Use a server-validated requirements manifest derived from Bunny compiler analysis where feasible. Do not trust client declarations. Reconcile dynamic device access, conditional/optional dependencies, aliases and thread semantics with the existing language implementation; report limitations and define an approved conservative validation policy before shipping. Do not silently declare unknown requirements compatible.

Revalidate on program edits, hardware changes, preset application and deployment. Preserve incompatible saved programs rather than deleting them. Show actionable reasons; filter or disable incompatible choices. Snapshot exact program source/revision for each round so later edits do not affect a running battle.

## 8. Composable tank presets

Presets belong to individual tanks, not a global player preset library. A preset can contain any combination of hardware, software and configuration sections; appearance is a proposed optional section for future extensibility. Bus-only presets are a first-class use of the same system.

Support named presets, Save As, update, load/apply, rename and delete. Allow selection of included sections when saving. Applying a preset replaces only included sections; other sections remain unchanged. Apply presets sequentially to compose a final configuration.

Example: apply **Merlin Build** (four-bus hardware, Mesh, Crazy BW program and bus settings), then **Weaponized Bus** (bus settings only). The latter must not alter hardware or software.

Bus configuration changes and preset switching are permitted in blue configuration bays and before battle begins, not during an active battle. Motor Pool is also a configuration context. Hardware presets describe authorized configurations and cannot grant hardware or bypass upgrade rules. Preserve presets after equipment changes, mark incompatible sections and allow correction; never silently rewrite or delete them.

Distinguish persistent saved defaults, editable deployment draft, and immutable round configuration. Proposed saving policy: rename automatically; save preset/program edits explicitly; save bus/default configuration when explicitly applied as a persistent change; deployment-only edits do not overwrite defaults unless the owner explicitly saves them. Confirm exact UI save semantics and unsaved-edit handling during reconciliation. Protect against accidental loss on tank switching, exit or disconnect.

## 9. Physical equipment inventory and allocation

Owning an item grants exactly one physical instance unless the player earns or acquires more. Every instance has a stable unique ID and catalog type ID. Two identical devices have different instance IDs. Equipment inventory is distinct from installation and from presets.

Hardware presets may describe alternative configurations that need the same item; they do not reserve or duplicate it merely by existing. Uninstalled items remain in the player's inventory. A physical instance cannot be installed/allocated to two simultaneously active tanks. Any future transfer, installation or reservation must be server-authoritative and atomic. Define reservation lifecycle across servers and active deployments, including release on round completion, cancellation and recovery after server failure.

Example: player owns one Mesh and selects two tanks. At most one tank can receive Mesh. A second Mesh requires earning/acquiring a second instance. A program that requires Mesh must be assigned to the tank that actually receives it.

## 10. Shared deployment validation

Use one reusable server-side compatibility and deployment validation service across Motor Pool, Engineering, Training Grounds, Campaign and Competitions. UI feedback should update as the draft changes, but server validation is authoritative.

Validate the final assembled configuration, not isolated presets or global ownership alone:

1. Player owns each selected tank; no duplicate tank selections or conflicting active reservations.
2. Player owns every requested limited equipment instance.
3. No instance is allocated more than once across selected tanks or conflicting deployments.
4. Each tank supports its assigned hardware, slots and device constraints.
5. Each tank's bus allocation is valid for its actual installed hardware and capacity.
6. Each tank's selected program satisfies its own installed device, thread and capability requirements.
7. All selected tanks satisfy applicable battle eligibility rules.
8. Atomically reserve tanks/equipment and create the validated deployment snapshot; reject stale drafts or conflicts without partial deployment.

Moving a Mesh from Merlin to Rattler must immediately revalidate both tanks' programs and bus configurations. Do not silently substitute equipment or programs or redistribute bus allocations. Block deployment until all errors are resolved and identify the affected tank and requirement.

The final round snapshot includes resolved equipment instance assignments, hardware configuration, bus allocation, exact program revision/source and applicable appearance settings. Saved edits elsewhere must not change a round already in progress. Training Grounds permits the explicitly authorized live configuration changes described above; it is not a competitive round.

## 11. Implementation phases

### Phase 1 — Ownership and persistence

Implement versioned player/tank records, equipment instance inventory foundation, ownership service, initial assignment and approved starter exchange behavior. Add idempotency, migration and failure handling. Provide minimal integration needed to verify assignment end-to-end.

### Phase 2 — Motor Pool and Training Grounds

Implement owned tank inventory, rename, colors, tank selection, seated entry for owners, on-foot entry for unassigned Recruits, borrowing, equipment locks and respawn lifecycle. Preserve existing blue bay and controls.

### Phase 3 — Programs and presets

Implement reusable program library, selected program attribute, compatibility requirements, tank-specific composable presets and approved save/default semantics. Integrate compatibility feedback with configuration UI.

### Phase 4 — Deployment engine

Implement shared final-configuration validation, multi-tank equipment allocation, atomic reservations and immutable round snapshots. Integrate existing supported deployment paths; do not build unrelated campaign or competition content.

Design all four phases together. Implement incrementally with tests and approval checkpoints. Avoid temporary schemas or duplicated validation logic that would require rewriting earlier phases.

## 12. Acceptance tests

- New Recruit enters on foot, tests multiple tanks, cancels confirmation, then accepts one assignment successfully; rejoin restores exactly one owned tank.
- Concurrent/duplicate assignment requests and ambiguous save failures never grant extra tanks or consume entitlement without ownership.
- Failed player load never overwrites inventory; stale writes cannot replace newer records.
- Owned tank entry starts seated in selected tank; single tank is preselected; owner can exit and return when unoccupied.
- Both temporary and owned tanks support bus changes; owned drivetrain/weapon cannot be changed freely.
- Borrower can operate advanced tank; owner cannot enter occupied seat; borrower cannot persist owner changes or claim upgraded/nonstandard tank.
- Eligible default borrowed tank assignment does not remove original owner's tank or duplicate limited equipment outside the new starter grant.
- Approved starter exchange preserves entitlement and tank count, does not duplicate equipment, and revalidates affected configurations.
- Rename and three colors survive rejoin; names are filtered and references remain stable.
- Tank-specific bus preset survives rejoin; applying bus-only preset leaves hardware and program unchanged; incompatible presets are retained with reasons.
- Mesh-dependent program is unavailable on a tank without Mesh; insufficient thread count also blocks selection/deployment.
- Two tanks with one Mesh cannot both deploy with it; assigning Mesh to one and Mesh-dependent code to the other fails; assigning both to the same tank succeeds if other requirements pass.
- Moving Mesh updates compatibility for both tanks; acquiring a second legitimate instance permits both to use Mesh.
- Client-forged equipment IDs, ownership, requirements or allocations are rejected by server.
- Concurrent deployments cannot reserve the same tank or item; cancellation and round completion release reservations safely.
- Deployment-only changes do not overwrite saved defaults; editing a saved program during a round does not alter its snapshot.
- Training destruction respawns at full health; campaign/challenge destruction prevents respawn until next round; ownership survives all destruction.
- Existing training, editor, Bunny runtime and gameplay regression tests remain passing; report baseline failures separately. Perform Roblox Studio acceptance tests for UI and multiplayer behavior; report anything not actually tested.

## 13. Decisions requiring approval during source reconciliation

The following are proposed details, not silently finalized requirements: exact starter exchange eligibility/frequency and recovery UI; borrowed-tank temporary programming/bus behavior and restoration; owner disconnect while a borrower is seated; unoccupied Auto behavior; exact save/default and draft recovery semantics; player color inheritance and appearance presets; starter hardware instance representation; compiler requirement inference for dynamic/optional dependencies; reservation/session recovery strategy and competition-specific round rules. Identify any additional source conflicts before implementation.

Out of scope: economy, acquisition UI, trading, selling, scrapping, rank progression, new cosmetic effects, and new campaign/competition content. Preserve extensibility without implementing speculative features.

