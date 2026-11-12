'use strict';
// Deliberately one imported model, uniform scale, no influence handling.
function resolveAsset(resource, bindings) {
  const match = Object.entries(bindings).find(([id, b]) => id === resource || b.source === resource);
  if (!match) return null;
  const [id, b] = match;
  if (typeof b.source !== 'string' || typeof b.model !== 'string' || !b.model || b.model.includes('/')) throw new Error(`Invalid Roblox asset binding '${id}'`);
  return { id, source: b.source, model: b.model };
}
function studioPlacement(manifest, bindings) {
  if (manifest.objects.length !== 1) return null;
  const item = manifest.objects[0], binding = resolveAsset(item.asset, bindings);
  if (!binding || Object.keys(item.influences || {}).length) return null;
  const m = item.transform;
  if (!Array.isArray(m) || m.length !== 16 || !m.every(Number.isFinite)) return null;
  const s = Math.hypot(m[0], m[1], m[2]);
  if (s <= 0 || [4, 8].some(i => Math.abs(Math.hypot(m[i], m[i + 1], m[i + 2]) - s) > s * 1e-6)) return null;
  for (const [a, b] of [[0, 4], [0, 8], [4, 8]]) if (Math.abs((m[a] * m[b] + m[a + 1] * m[b + 1] + m[a + 2] * m[b + 2]) / s ** 2) > 1e-6) return null;
  const det = m[0] * (m[5] * m[10] - m[9] * m[6]) - m[4] * (m[1] * m[10] - m[9] * m[2]) + m[8] * (m[1] * m[6] - m[5] * m[2]);
  if (det <= 0) return null;
  const y = Math.asin(Math.max(-1, Math.min(1, m[8] / s))), cosine = Math.cos(y);
  const x = Math.abs(cosine) > 1e-6 ? Math.atan2(-m[9], m[10]) : Math.atan2(m[6], m[5]);
  const z = Math.abs(cosine) > 1e-6 ? Math.atan2(-m[4], m[0]) : 0;
  return { ...binding, id: item.id, assetId: binding.id, position: m.slice(12, 15), rotation: [x, y, z].map(n => n * 180 / Math.PI), scale: s };
}
module.exports = { resolveAsset, studioPlacement };
