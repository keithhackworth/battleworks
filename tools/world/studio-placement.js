'use strict';
// Bounded imported placements with uniform scale and optional fixed collision/durability.
function resolveAsset(resource, bindings) {
  const match = Object.entries(bindings).find(([id, b]) => id === resource || b.source === resource);
  if (!match) return null;
  const [id, b] = match;
  if (typeof b.source !== 'string' || typeof b.model !== 'string' || !b.model || b.model.includes('/')) throw new Error(`Invalid Roblox asset binding '${id}'`);
  return { id, source: b.source, model: b.model, ...(b.collider ? { collider: b.collider } : {}) };
}
function interactionFor(influences = {}, binding) {
  const supported = { physical: ['movable', 'destructible', 'indestructible', 'hp'], movement: ['collision', 'traversable'] };
  for (const [category, values] of Object.entries(influences)) {
    if (!supported[category] || !values || typeof values !== 'object' || Array.isArray(values)) throw new Error(`Unsupported imported-model influence '${category}'.`);
    for (const key of Object.keys(values)) if (!supported[category].includes(key)) throw new Error(`Unsupported imported-model influence '${category}.${key}'.`);
  }
  const p = influences.physical || {}, m = influences.movement || {};
  for (const [key, value] of Object.entries(p)) if (key !== 'hp' && typeof value !== 'boolean') throw new Error(`physical.${key} must be boolean.`);
  if (p.movable === true) throw new Error('physical.movable=true is not supported: pushing and tipping are not implemented.');
  if (p.destructible !== undefined && p.indestructible !== undefined && p.destructible === p.indestructible) throw new Error('Conflicting destructible/indestructible settings.');
  if (m.collision !== undefined && !['solid', 'none'].includes(m.collision)) throw new Error("movement.collision must be 'solid' or 'none'.");
  if (m.traversable !== undefined && typeof m.traversable !== 'boolean') throw new Error('movement.traversable must be boolean.');
  if ((m.collision === 'solid' && m.traversable === true) || (m.collision === 'none' && m.traversable === false)) throw new Error('movement.collision contradicts movement.traversable.');
  const hp = p.hp ?? 100;
  if (typeof hp !== 'number' || !Number.isFinite(hp) || hp < 0) throw new Error('physical.hp must be a finite nonnegative number.');
  const solid = m.collision === 'solid' || m.traversable === false;
  const destructible = p.destructible === true || p.indestructible === false;
  if (!solid && !destructible) return null;
  const collider = binding.collider;
  if (!collider || ['widthFraction', 'depthFraction', 'heightFraction'].some(k => typeof collider[k] !== 'number' || !Number.isFinite(collider[k]) || collider[k] <= 0 || collider[k] > 1)) throw new Error(`Asset '${binding.id}' requires collider width/depth/height fractions in (0,1]. Set collider on its entry in worlds/roblox-assets.json, not in world influences or model definitions.`);
  return { solid, destructible, hp, collider };
}
const MaxPlacements = 512;
function placementIssue(manifest, bindings) {
  if (!manifest.objects.length || manifest.objects.length > MaxPlacements) return `Imported worlds require 1–${MaxPlacements} model placements.`;
  const ids = new Set();
  for (const item of manifest.objects) {
    if (ids.has(item.id)) return `Duplicate imported placement '${item.id}'.`;
    ids.add(item.id);
    const issue = itemIssue(item, bindings);
    if (issue) return `Object '${item.id}': ${issue}`;
  }
  return null;
}
function studioPlacements(manifest, bindings) {
  if (placementIssue(manifest, bindings)) return null;
  return manifest.objects.map(item => studioPlacement({objects:[item]}, bindings));
}
function itemIssue(item, bindings) {
  const binding = resolveAsset(item.asset, bindings);
  if (!binding) return `Resource '${item.asset}' has no Roblox asset mapping.`;
  const m = item.transform;
  if (!Array.isArray(m) || m.length !== 16 || !m.every(Number.isFinite)) return 'Invalid imported-model transform.';
  const s = Math.hypot(m[0], m[1], m[2]);
  if (s <= 0 || [4, 8].some(i => Math.abs(Math.hypot(m[i], m[i + 1], m[i + 2]) - s) > s * 1e-6)) return 'Imported-model placement requires positive uniform scale.';
  for (const [a, b] of [[0, 4], [0, 8], [4, 8]]) if (Math.abs((m[a] * m[b] + m[a + 1] * m[b + 1] + m[a + 2] * m[b + 2]) / s ** 2) > 1e-6) return 'Imported-model placement does not support sheared transforms.';
  const det = m[0] * (m[5] * m[10] - m[9] * m[6]) - m[4] * (m[1] * m[10] - m[9] * m[2]) + m[8] * (m[1] * m[6] - m[5] * m[2]);
  if (det <= 0) return 'Imported-model placement does not support reflected transforms.';
  try {
    const interaction = interactionFor(item.influences, binding);
    if (interaction && (Math.abs(m[1] / s) > 1e-6 || Math.abs(m[9] / s) > 1e-6 || m[5] / s < 1 - 1e-6)) return 'Interactive imported models must be upright (yaw rotation only).';
  } catch (error) { return error.message; }
  return null;
}
function studioPlacement(manifest, bindings) {
  if (manifest.objects.length !== 1 || placementIssue(manifest, bindings)) return null;
  const item = manifest.objects[0], binding = resolveAsset(item.asset, bindings), m = item.transform;
  const s = Math.hypot(m[0], m[1], m[2]);
  const y = Math.asin(Math.max(-1, Math.min(1, m[8] / s))), cosine = Math.cos(y);
  const x = Math.abs(cosine) > 1e-6 ? Math.atan2(-m[9], m[10]) : Math.atan2(m[6], m[5]);
  const z = Math.abs(cosine) > 1e-6 ? Math.atan2(-m[4], m[0]) : 0;
  // Equivalent Euler triples can contain 180-degree roll for upright yaw >90.
  const interaction = interactionFor(item.influences, binding);
  const rotation = interaction ? [0, Math.atan2(m[8], m[0]) * 180 / Math.PI, 0] : [x, y, z].map(n => n * 180 / Math.PI);
  return { ...binding, id: item.id, assetId: binding.id, position: m.slice(12, 15), rotation, scale: s, interaction };
}
module.exports = { resolveAsset, studioPlacement, studioPlacements, placementIssue, interactionFor, MaxPlacements };
