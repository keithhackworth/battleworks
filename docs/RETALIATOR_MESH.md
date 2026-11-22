# Retaliator Mesh

Retaliator Mesh is an optional reactive damage sensor. It uses the same 100-point bus as the drivetrain, turret, weapon, and scanner array. It operates at 25% allocation or above when installed. It provides no damage reduction. A tank also needs a running BW program registered for `OnDamageTaken`.

## Try the example

Select **Retaliator Mesh** in the [Innovation Lab](INNOVATION_LAB.md). The Lab equips and powers the Mesh on its experimental tank. The Playground Garage leaves lab equipment unavailable.

Classic Garage still supports custom setup. Free at least 25 bus points, select **Equip Retaliator Mesh**, and set its allocation to 25% or more before saving. To try the example there, run `programs/examples/retaliator-mesh.bw` from the BW Editor on a tracked Boomer with drivetrain power.

## Payload and timing

A surviving hit that does positive damage queues one event with exactly these keys:

```python
{amount: 25, direction: 135, remaining_hp: 75}
```

- `amount` is the HP actually removed. `remaining_hp` is the HP immediately after the hit.
- `direction` is in degrees from 0 inclusive to 360 exclusive, measured clockwise relative to the chassis heading at impact. 0° is directly ahead, 90° is to the right, and 180° is behind. The bearing points back along the incoming projectile's travel at impact. A missing or effectively vertical travel direction produces BW `null`.
- The payload contains no attacker identity or coordinates. Multiple hits queue independently in authoritative impact order, subject to the existing queue limit. A handler runs on an available BW slot.
- A lethal hit stops the invocation immediately and discards its work. No handler runs for the lethal hit. A replacement or restarted program begins with an empty queue.
