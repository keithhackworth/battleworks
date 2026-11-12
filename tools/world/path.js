'use strict';
const SUPPORTED = new Set('MmLlHhVvCcSsZz');
const distance = (a, b) => Math.hypot(b[0] - a[0], b[1] - a[1]);
function tokenize(source) {
  if (typeof source !== 'string' || !source.trim()) throw new Error('expected a nonempty SVG path string');
  if (source.length > 100000) throw new Error('SVG path exceeds 100,000 characters');
  const out = []; let pos = 0;
  while (pos < source.length) {
    const rest = source.slice(pos);
    const separator = rest.match(/^[\s,]+/);
    if (separator) { if (/,[\s]*,/.test(separator[0])) throw new Error(`invalid comma separator at offset ${pos}`); pos += separator[0].length; continue; }
    if (/^[a-zA-Z]/.test(rest)) {
      if (!SUPPORTED.has(rest[0])) throw new Error(`unsupported SVG command '${rest[0]}' at offset ${pos}`);
      out.push(rest[0]); pos++; continue;
    }
    const match = rest.match(/^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/);
    if (!match) throw new Error(`invalid SVG token at offset ${pos}`);
    const n = Number(match[0]); if (!Number.isFinite(n)) throw new Error(`non-finite SVG coordinate at offset ${pos}`);
    out.push(n); pos += match[0].length;
  }
  return out;
}
function flattenPath(source, curveSamples = 32) {
  if (!Number.isInteger(curveSamples) || curveSamples < 4 || curveSamples > 512) throw new Error('curveSamples must be an integer from 4 to 512');
  const tokens = tokenize(source), subpaths = [];
  let pointCount = 0;
  let i = 0, command, current = [0, 0], active, previousControl, moved = false;
  function begin(p) { active = { points: [p.slice()], closed: false }; subpaths.push(active); }
  function line(p) {
    if (++pointCount > 200000) throw new Error('SVG curve sampling exceeds 200,000 points');
    if (!p.every(Number.isFinite)) throw new Error('non-finite sampled SVG geometry');
    if (!active) begin(current);
    active.points.push(p); current = p;
  }
  function number() { if (typeof tokens[i] !== 'number') throw new Error(`command '${command}' is missing coordinates (token ${i})`); return tokens[i++]; }
  function point(relative, origin = current) {
    const p = [number(), number()]; return relative ? [origin[0] + p[0], origin[1] + p[1]] : p;
  }
  while (i < tokens.length) {
    if (typeof tokens[i] === 'string') command = tokens[i++];
    else if (!command) throw new Error(`expected SVG command at token ${i}`);
    const kind = command.toUpperCase(), relative = command !== kind;
    if (!moved && kind !== 'M') throw new Error('SVG path must begin with M or m');
    if (kind === 'Z') {
      if (active) { if (distance(current, active.points[0]) > 0) line(active.points[0].slice()); active.closed = true; current = active.points[0].slice(); active = undefined; }
      previousControl = undefined; command = undefined; continue;
    }
    if (kind === 'M') {
      current = point(relative); begin(current); moved = true; previousControl = undefined;
      command = relative ? 'l' : 'L'; // Additional moveto coordinate pairs are lines.
    } else if (kind === 'L') { line(point(relative)); previousControl = undefined; }
    else if (kind === 'H') { const x = number(); line([relative ? current[0] + x : x, current[1]]); previousControl = undefined; }
    else if (kind === 'V') { const y = number(); line([current[0], relative ? current[1] + y : y]); previousControl = undefined; }
    else {
      const start = current.slice();
      const a = kind === 'S' ? (previousControl ? [2 * start[0] - previousControl[0], 2 * start[1] - previousControl[1]] : start.slice()) : point(relative, start);
      const b = point(relative, start), end = point(relative, start);
      for (let step = 1; step <= curveSamples; step++) {
        const t = step / curveSamples, u = 1 - t;
        line([0, 1].map(axis => u ** 3 * start[axis] + 3 * u ** 2 * t * a[axis] + 3 * u * t ** 2 * b[axis] + t ** 3 * end[axis]));
      }
      current = end; previousControl = b;
    }
  }
  return subpaths.filter(s => s.points.length > 1).map(s => {
    const lengths = [0]; for (let n = 1; n < s.points.length; n++) lengths.push(lengths[n - 1] + distance(s.points[n - 1], s.points[n]));
    if (!Number.isFinite(lengths.at(-1))) throw new Error('SVG arc length is non-finite');
    return { ...s, lengths, length: lengths.at(-1) };
  });
}
function sampleAt(path, d) {
  let lo = 1, hi = path.lengths.length - 1;
  while (lo < hi) { const mid = (lo + hi) >> 1; if (path.lengths[mid] < d) lo = mid + 1; else hi = mid; }
  // Skip zero-length samples, retaining the first usable segment at the start.
  while (lo < path.points.length - 1 && path.lengths[lo] === path.lengths[lo - 1]) lo++;
  let a = path.points[lo - 1], b = path.points[lo], span = path.lengths[lo] - path.lengths[lo - 1];
  if (!span) { for (let j = lo - 1; j > 0; j--) if (path.lengths[j] > path.lengths[j - 1]) { a = path.points[j - 1]; b = path.points[j]; span = path.lengths[j] - path.lengths[j - 1]; break; } }
  const t = span ? Math.max(0, Math.min(1, (d - path.lengths[lo - 1]) / span)) : 0;
  return { point: [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t], tangent: [b[0] - a[0], b[1] - a[1]] };
}
function contains(subpaths, [x, y]) {
  let inside = false; // Even-odd fill, including holes and disjoint subpaths.
  for (const { points } of subpaths) for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    const a = points[j], b = points[i];
    const cross = (x - a[0]) * (b[1] - a[1]) - (y - a[1]) * (b[0] - a[0]);
    if (Math.abs(cross) < 1e-9 && x >= Math.min(a[0], b[0]) && x <= Math.max(a[0], b[0]) && y >= Math.min(a[1], b[1]) && y <= Math.max(a[1], b[1])) return true;
    if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
  }
  return inside;
}
module.exports = { flattenPath, sampleAt, contains };
