'use strict';
// Column-major matrices, column vectors: local = T * Rx * Ry * Rz * S.
const identity = () => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
function multiply(a, b) {
  const out = Array(16).fill(0);
  for (let col = 0; col < 4; col++) for (let row = 0; row < 4; row++) {
    for (let k = 0; k < 4; k++) out[col * 4 + row] += a[k * 4 + row] * b[col * 4 + k];
  }
  return out;
}
function translation([x, y, z]) {
  const m = identity(); m[12] = x; m[13] = y; m[14] = z; return m;
}
function trs(position = [0, 0, 0], rotation = [0, 0, 0], scale = [1, 1, 1]) {
  const [x, y, z] = rotation.map(n => (n % 360) * Math.PI / 180);
  const [cx, sx, cy, sy, cz, sz] = [Math.cos(x), Math.sin(x), Math.cos(y), Math.sin(y), Math.cos(z), Math.sin(z)];
  const rx = [1, 0, 0, 0, 0, cx, sx, 0, 0, -sx, cx, 0, 0, 0, 0, 1];
  const ry = [cy, 0, -sy, 0, 0, 1, 0, 0, sy, 0, cy, 0, 0, 0, 0, 1];
  const rz = [cz, sz, 0, 0, -sz, cz, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  const s = identity(); [s[0], s[5], s[10]] = typeof scale === 'number' ? [scale, scale, scale] : scale;
  return multiply(multiply(multiply(multiply(translation(position), rx), ry), rz), s);
}
function summarize(m) {
  // Full matrix remains authoritative when nested nonuniform scales cause shear.
  return { position: m.slice(12, 15), scale: [Math.hypot(...m.slice(0, 3)), Math.hypot(...m.slice(4, 7)), Math.hypot(...m.slice(8, 11))], transform: m };
}
module.exports = { identity, multiply, translation, trs, summarize };
