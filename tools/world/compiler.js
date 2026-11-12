'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { flattenPath, sampleAt, contains } = require('./path');
const { identity, multiply, translation, trs, summarize } = require('./transform');
const object = v => v !== null && typeof v === 'object' && !Array.isArray(v);
const own = (v, k) => Object.hasOwn(v, k);
const TYPES = new Set(['model', 'group', 'path', 'region', 'repeat']);
const COMMON = ['type', 'ref', 'position', 'rotation', 'scale', 'influences', 'repeat'];
const FIELDS = {
  model: ['asset'], group: ['children'],
  path: ['path', 'spacing', 'overlap', 'orientToPath', 'positionJitter', 'rotationJitter', 'curveSamples', 'item'],
  region: ['path', 'count', 'minSeparation', 'maxAttempts', 'randomRotation', 'rotationJitter', 'scaleRange', 'curveSamples', 'item'],
  repeat: ['count', 'offset', 'item'],
};
class WorldError extends Error {
  constructor(file, id, property, message) { super(`${file} :: ${id} :: ${property}: ${message}`); this.detail = message; this.name = 'WorldError'; this.file = file; this.id = id; this.property = property; }
}
function merge(base, override) {
  if (!object(base) || !object(override)) return structuredClone(override);
  const out = structuredClone(base);
  for (const [key, value] of Object.entries(override)) {
    if (['__proto__', 'prototype', 'constructor'].includes(key)) throw new Error(`unsafe JSON key '${key}'`);
    out[key] = own(base, key) ? merge(base[key], value) : structuredClone(value);
  }
  return out;
}
function rng(seed, id, purpose) {
  let state = createHash('sha256').update(JSON.stringify([seed, id, purpose])).digest().readUInt32LE(0);
  return () => {
    state = (state + 0x6D2B79F5) >>> 0;
    let t = Math.imul(state ^ state >>> 15, 1 | state);
    t = (t + Math.imul(t ^ t >>> 7, 61 | t)) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (object(value)) return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  return Object.is(value, -0) ? 0 : value;
}
function serialize(manifest) { return JSON.stringify(canonical(manifest), null, 2) + '\n'; }
function compileWorld(world, registry = {}, options = {}) {
  const file = options.source || '<world>', origins = options.origins || new Map();
  const definitions = new Map(), resolved = new Map(), used = new Set(), ids = new Set(), geometry = new Map();
  const objects = [], seed = world && own(world, 'seed') ? world.seed : 0;
  const maxObjects = options.maxObjects ?? 100000, maxNodes = options.maxNodes ?? 200000;
  let nodes = 0, generatedPathSegments = 0, graphNodes = 0, diagnosticSource = file;
  const fail = (id, prop, message, source = diagnosticSource) => { throw new WorldError(source, id, prop, message); };
  function json(v, id, prop, depth = 0, source = file) {
    if (depth > 64) fail(id, prop, 'JSON nesting exceeds 64', source);
    if (v === null || typeof v === 'string' || typeof v === 'boolean') return;
    if (typeof v === 'number' && Number.isFinite(v)) return;
    if (Array.isArray(v)) { v.forEach((n, i) => json(n, id, `${prop}[${i}]`, depth + 1, source)); return; }
    if (object(v)) {
      for (const [k, n] of Object.entries(v)) {
        if (['__proto__', 'prototype', 'constructor'].includes(k)) fail(id, `${prop}.${k}`, 'unsafe JSON key', source);
        json(n, id, `${prop}.${k}`, depth + 1, source);
      }
      return;
    }
    fail(id, prop, 'expected finite JSON data', source);
  }
  const finite = (n, id, prop, min = -Infinity, max = Infinity) => {
    if (typeof n !== 'number' || !Number.isFinite(n) || n < min || n > max) fail(id, prop, `expected finite number in [${min}, ${max}]`);
  };
  function integer(n, id, prop, min = 0, max = 10000) { finite(n, id, prop, min, max); if (!Number.isInteger(n)) fail(id, prop, 'expected integer'); }
  function vector(v, id, prop, positive = false) {
    if (!Array.isArray(v) || v.length !== 3) fail(id, prop, 'expected [x, y, z]');
    v.forEach((n, i) => { finite(n, id, `${prop}[${i}]`, positive ? Number.MIN_VALUE : -Infinity); });
  }
  function scale(v, id, prop) { if (typeof v === 'number') finite(v, id, prop, Number.MIN_VALUE); else vector(v, id, prop, true); }
  function name(n, id, prop) {
    if (typeof n !== 'string' || !/^[A-Za-z0-9_][A-Za-z0-9_.:-]*$/.test(n)) fail(id, prop, 'expected a nonempty ID using letters, digits, _, ., :, - (no /)');
  }
  function keys(v, allowed, id, prefix = '') {
    for (const k of Object.keys(v)) if (!allowed.includes(k)) fail(id, prefix + k, 'unknown property');
  }
  function influences(v, id) {
    if (!object(v)) fail(id, 'influences', 'expected an object');
    for (const [category, fields] of Object.entries(v)) {
      if (!object(fields)) fail(id, `influences.${category}`, 'expected a metadata object');
      for (const [key, n] of Object.entries(fields)) {
        const prop = `influences.${category}.${key}`;
        if (category === 'physical') {
          if (['mass', 'friction', 'hp'].includes(key)) finite(n, id, prop, 0);
          if (['movable', 'destructible', 'indestructible'].includes(key) && typeof n !== 'boolean') fail(id, prop, 'expected boolean');
        }
        if (category === 'movement') {
          if (['tractionMultiplier', 'speedMultiplier'].includes(key)) finite(n, id, prop, 0);
          if (key === 'traversable' && typeof n !== 'boolean') fail(id, prop, 'expected boolean');
          if (key === 'collision' && (typeof n !== 'string' || !n.trim())) fail(id, prop, 'expected a nonempty collision category');
        }
      }
      if (category === 'physical' && own(fields, 'destructible') && own(fields, 'indestructible') && fields.destructible === fields.indestructible) fail(id, 'influences.physical', 'destructible and indestructible contradict each other');
    }
  }
  function asset(a, id) {
    function resource(p, prop) { if (typeof p !== 'string' || !p.trim() || !/\.glb$/i.test(p) || p.includes('\0')) fail(id, prop, 'expected a symbolic .glb resource path'); }
    if (typeof a === 'string') { resource(a, 'asset'); return; }
    if (!object(a)) fail(id, 'asset', 'expected a .glb path or selection object');
    keys(a, ['selection', 'items'], id, 'asset.');
    if (!['single', 'random', 'weighted'].includes(a.selection)) fail(id, 'asset.selection', 'expected single, random or weighted');
    if (!Array.isArray(a.items) || !a.items.length || a.items.length > 10000) fail(id, 'asset.items', 'expected 1..10,000 candidates');
    let total = 0;
    a.items.forEach((candidate, i) => {
      const prop = `asset.items[${i}]`;
      if (!object(candidate)) fail(id, prop, 'expected a candidate object');
      keys(candidate, ['path', 'weight', 'rotation', 'scale'], id, prop + '.');
      resource(candidate.path, prop + '.path');
      if (own(candidate, 'rotation')) vector(candidate.rotation, id, prop + '.rotation');
      if (own(candidate, 'scale')) scale(candidate.scale, id, prop + '.scale');
      if (own(candidate, 'weight')) finite(candidate.weight, id, prop + '.weight', 0);
      total += candidate.weight ?? 1;
    });
    if (!Number.isFinite(total) || (a.selection === 'weighted' && total <= 0)) fail(id, 'asset.items', 'weighted candidates must have a finite positive total weight');
  }
  function instance(v, id, requireId = false) {
    if (!object(v)) fail(id, 'instance', 'expected an object');
    if (requireId) name(v.id, id, 'id');
    if (own(v, 'id')) name(v.id, id, 'id');
    if (typeof v.ref !== 'string') fail(id, 'ref', 'expected a definition reference');
    if (!definitions.has(v.ref)) fail(id, 'ref', `missing reference '${v.ref}'`);
  }
  function paths(spec, id) {
    const key = JSON.stringify([spec.path, spec.curveSamples ?? 32]);
    if (!geometry.has(key)) {
      try { geometry.set(key, flattenPath(spec.path, spec.curveSamples ?? 32)); }
      catch (e) { fail(id, 'path', e.message); }
    }
    const paths = geometry.get(key);
    if (!paths.length || !paths.some(p => p.length > 0)) fail(id, 'path', 'expected nonzero drawable path geometry');
    return paths;
  }
  function validate(spec, id) {
    if (!object(spec) || !TYPES.has(spec.type)) fail(id, 'type', 'expected model, group, path, region or repeat');
    keys(spec, [...COMMON, ...FIELDS[spec.type]], id);
    if (own(spec, 'position')) vector(spec.position, id, 'position');
    if (own(spec, 'rotation')) vector(spec.rotation, id, 'rotation');
    if (own(spec, 'scale')) scale(spec.scale, id, 'scale');
    if (own(spec, 'influences')) influences(spec.influences, id);
    if (own(spec, 'repeat')) {
      if (!object(spec.repeat)) fail(id, 'repeat', 'expected {count, offset}');
      keys(spec.repeat, ['count', 'offset'], id, 'repeat.'); integer(spec.repeat.count, id, 'repeat.count'); vector(spec.repeat.offset, id, 'repeat.offset');
    }
    if (spec.type === 'model') asset(spec.asset, id);
    if (spec.type === 'group') {
      if (!Array.isArray(spec.children)) fail(id, 'children', 'expected an instance array');
      const siblings = new Set();
      spec.children.forEach((child, i) => { instance(child, `${id}/children[${i}]`, true); if (siblings.has(child.id)) fail(id, 'children', `duplicate child ID '${child.id}'`); siblings.add(child.id); });
    }
    if (['path', 'region', 'repeat'].includes(spec.type)) instance(spec.item, `${id}/item`);
    if (spec.type === 'repeat') { integer(spec.count, id, 'count'); vector(spec.offset, id, 'offset'); }
    if (spec.type === 'path') {
      finite(spec.spacing, id, 'spacing', Number.MIN_VALUE); finite(spec.overlap ?? 0, id, 'overlap', 0);
      if ((spec.overlap ?? 0) >= spec.spacing) fail(id, 'overlap', 'must be smaller than spacing');
      if (own(spec, 'orientToPath') && typeof spec.orientToPath !== 'boolean') fail(id, 'orientToPath', 'expected boolean');
      if (own(spec, 'positionJitter')) { vector(spec.positionJitter, id, 'positionJitter'); spec.positionJitter.forEach(n => finite(n, id, 'positionJitter', 0)); }
      paths(spec, id);
    }
    if (own(spec, 'curveSamples')) integer(spec.curveSamples, id, 'curveSamples', 4, 512);
    if (own(spec, 'rotationJitter')) { vector(spec.rotationJitter, id, 'rotationJitter'); spec.rotationJitter.forEach(n => finite(n, id, 'rotationJitter', 0)); }
    if (spec.type === 'region') {
      integer(spec.count, id, 'count'); finite(spec.minSeparation ?? 0, id, 'minSeparation', 0);
      if (own(spec, 'maxAttempts')) integer(spec.maxAttempts, id, 'maxAttempts', 1, 1000000);
      if (own(spec, 'randomRotation') && typeof spec.randomRotation !== 'boolean') fail(id, 'randomRotation', 'expected boolean');
      if (own(spec, 'scaleRange')) {
        if (!Array.isArray(spec.scaleRange) || spec.scaleRange.length !== 2) fail(id, 'scaleRange', 'expected [minimum, maximum]');
        finite(spec.scaleRange[0], id, 'scaleRange[0]', Number.MIN_VALUE); finite(spec.scaleRange[1], id, 'scaleRange[1]', spec.scaleRange[0]);
      }
      const shape = paths(spec, id);
      if (shape.some(p => !p.closed)) fail(id, 'path', 'region subpaths must be explicitly closed with Z');
      for (const sub of shape) {
        const p = sub.points; let area = 0;
        for (let i = 1; i < p.length; i++) area += p[i - 1][0] * p[i][1] - p[i][0] * p[i - 1][1];
        if (!Number.isFinite(area) || Math.abs(area) < 1e-9) fail(id, 'path', 'region subpath has zero signed area; use simple closed polygons');
      }
    }
  }
  function resolve(id, chain = []) {
    if (chain.length >= 64) fail(id, 'ref', 'reference depth exceeds 64');
    if (!definitions.has(id)) fail(chain.at(-1) || '<registry>', 'ref', `missing reference '${id}'`);
    if (chain.includes(id)) fail(id, 'ref', `cyclic reference: ${[...chain, id].join(' -> ')}`, origins.get(id) || file);
    if (resolved.has(id)) return resolved.get(id);
    const raw = definitions.get(id);
    const base = own(raw, 'ref') ? resolve(raw.ref, [...chain, id]).spec : {};
    const ownSpec = { ...raw }; delete ownSpec.ref;
    const entry = { spec: merge(base, ownSpec), chain: [...(own(raw, 'ref') ? resolve(raw.ref).chain : []), id] };
    resolved.set(id, entry); return entry;
  }
  function effective(v, id) {
    instance(v, id);
    const entry = resolve(v.ref), overrides = { ...v }; delete overrides.id; delete overrides.ref;
    if (own(v, 'type') && v.type !== entry.spec.type) fail(id, 'type', 'an instance cannot change its definition type');
    const spec = merge(entry.spec, overrides); validate(spec, id); return { spec, references: entry.chain };
  }
  // JSON safety is checked before merging, including imported and unused entries.
  json(world, '<world>', 'world'); json(registry, '<registry>', 'definitions');
  if (!object(world)) fail('<world>', 'world', 'expected a JSON object');
  keys(world, ['version', 'id', 'name', 'seed', 'definitionFiles', 'definitions', 'instances', 'assetScale'], '<world>');
  if (own(world, 'id')) name(world.id, '<world>', 'id');
  if (own(world, 'name') && (typeof world.name !== 'string' || !world.name.trim())) fail('<world>', 'name', 'expected a nonempty display name');
  if (own(world, 'assetScale') && (typeof world.assetScale !== 'number' || !Number.isFinite(world.assetScale) || world.assetScale <= 0)) fail('<world>', 'assetScale', 'expected a finite positive uniform scale');
  if (world.version !== 1) fail('<world>', 'version', 'expected version 1');
  if (!(typeof seed === 'string' || (typeof seed === 'number' && Number.isSafeInteger(seed)))) fail('<world>', 'seed', 'expected a string or safe integer');
  if (!object(registry) || (own(world, 'definitions') && !object(world.definitions))) fail('<registry>', 'definitions', 'expected an object keyed by definition ID');
  for (const collection of [registry, world.definitions || {}]) for (const [id, spec] of Object.entries(collection)) {
    name(id, id, 'definition ID'); if (definitions.has(id)) fail(id, 'definition', 'duplicate definition ID');
    if (!object(spec)) fail(id, 'definition', 'expected an object', origins.get(id) || file);
    definitions.set(id, spec);
  }
  if (own(world, 'definitionFiles') && (!Array.isArray(world.definitionFiles) || world.definitionFiles.some(p => typeof p !== 'string' || !p))) fail('<world>', 'definitionFiles', 'expected JSON file paths');
  if (!Array.isArray(world.instances)) fail('<world>', 'instances', 'expected an instance array');
  // Walk effective edges, including overrides, to validate unused definitions.
  function graph(v, chain, location) {
    if (++graphNodes > maxNodes) fail(location, 'ref', 'definition validation exceeds node limit');
    if (chain.length > 64) fail(location, 'ref', 'reference depth exceeds 64');
    if (chain.includes(v.ref)) fail(location, 'ref', `cyclic reference: ${[...chain, v.ref].join(' -> ')}`);
    const before = diagnosticSource;
    diagnosticSource = Object.keys(v).some(k => !['id', 'ref'].includes(k)) ? before : (origins.get(v.ref) || before);
    try {
      const { spec } = effective(v, location), next = [...chain, v.ref];
      if (spec.type === 'group') spec.children.forEach(child => graph(child, next, `${location}/${child.id}`));
      else if (spec.item) graph(spec.item, next, `${location}/item`);
    } finally { diagnosticSource = before; }
  }
  for (const id of [...definitions.keys()].sort()) {
    graph({ ref: id }, [], id);
  }
  function jitter(amount, id, purpose) {
    const random = rng(seed, id, purpose); return (amount || [0, 0, 0]).map(n => (random() * 2 - 1) * n);
  }
  function emit(spec, id, parent, metadata, references, provenance) {
    let candidate, index = 0;
    if (typeof spec.asset === 'string') candidate = { path: spec.asset };
    else {
      const { items, selection } = spec.asset, random = rng(seed, id, 'asset');
      if (selection === 'random') index = Math.floor(random() * items.length);
      if (selection === 'weighted') {
        let pick = random() * items.reduce((sum, item) => sum + (item.weight ?? 1), 0);
        index = items.length - 1;
        for (let i = 0; i < items.length; i++) { pick -= items[i].weight ?? 1; if (pick < 0) { index = i; break; } }
      }
      candidate = items[index];
    }
    const matrix = multiply(multiply(parent, trs([0, 0, 0], candidate.rotation, candidate.scale)), trs([0,0,0], [0,0,0], world.assetScale ?? 1));
    if (!matrix.every(Number.isFinite)) fail(id, 'transform', 'composed transform is non-finite');
    if (objects.length >= maxObjects) fail(id, 'objects', `output exceeds ${maxObjects} objects`);
    const summary = summarize(matrix);
    if (!summary.scale.every(n => Number.isFinite(n) && n > 0)) fail(id, 'scale', 'composed scale is degenerate or non-finite');
    const item = { id, source: references.at(-1), asset: candidate.path, ...summary, influences: metadata };
    if (options.provenance !== false) item.provenance = { references, ...provenance, candidate: index };
    objects.push(item);
  }
  function expand(v, id, parent, inherited, active = [], provenance = {}, trace = []) {
    if (++nodes > maxNodes) fail(id, 'instances', `expansion exceeds ${maxNodes} nodes`);
    if (active.length >= 64) fail(id, 'ref', 'reference depth exceeds 64');
    if (active.includes(v.ref)) fail(id, 'ref', `cyclic reference: ${[...active, v.ref].join(' -> ')}`);
    if (ids.has(id)) fail(id, 'id', 'duplicate hierarchical instance ID'); ids.add(id);
    const { spec, references } = effective(v, id);
    references.forEach(ref => used.add(ref));
    const chain = [...active, v.ref], referenceTrace = [...trace, ...references], matrix = multiply(parent, trs(spec.position, spec.rotation, spec.scale));
    const metadata = merge(inherited, spec.influences || {});
    influences(metadata, id);
    if (spec.repeat) {
      const base = { ...spec }; delete base.repeat; delete base.position; delete base.rotation; delete base.scale; delete base.influences;
      // Expand the resolved specification without re-applying its defaults/TRS.
      for (let i = 0; i < spec.repeat.count; i++) expandResolved(base, `${id}/repeat_${String(i).padStart(3, '0')}`, multiply(matrix, translation(spec.repeat.offset.map(n => n * i))), metadata, chain, provenance, false, referenceTrace);
      return;
    }
    expandResolved(spec, id, matrix, metadata, chain, provenance, true, referenceTrace);
  }
  function expandResolved(spec, id, matrix, metadata, chain, provenance, reserved = false, trace = chain) {
    if (!reserved) { if (++nodes > maxNodes) fail(id, 'instances', `expansion exceeds ${maxNodes} nodes`); if (ids.has(id)) fail(id, 'id', 'duplicate hierarchical instance ID'); ids.add(id); }
    if (spec.type === 'model') { emit(spec, id, matrix, metadata, trace, provenance); return; }
    if (spec.type === 'group') {
      spec.children.forEach(child => expand(child, `${id}/${child.id}`, matrix, metadata, chain, provenance, trace)); return;
    }
    if (spec.type === 'repeat') {
      for (let i = 0; i < spec.count; i++) expand(spec.item, `${id}/repeat_${String(i).padStart(3, '0')}`, multiply(matrix, translation(spec.offset.map(n => n * i))), metadata, chain, { ...provenance, repeatIndex: i }, trace);
      return;
    }
    if (spec.type === 'path') {
      const step = spec.spacing - (spec.overlap || 0); let segment = 0;
      paths(spec, id).forEach((sub, subpath) => {
        if (sub.length === 0) return;
        const epsilon = Math.min(step * 1e-8, Math.max(1, sub.length) * 1e-10);
        const count = sub.closed ? Math.max(1, Math.ceil((sub.length - epsilon) / step)) : Math.floor((sub.length + epsilon) / step) + 1;
        if (!Number.isSafeInteger(count) || count > maxNodes - nodes) fail(id, 'spacing', 'path would exceed the expansion limit');
        for (let i = 0; i < count; i++) {
          const distance = Math.min(i * step, sub.length), at = sampleAt(sub, distance), child = `${id}/segment_${String(segment++).padStart(3, '0')}`;
          const position = jitter(spec.positionJitter, child, 'position'); position[0] += at.point[0]; position[2] += at.point[1];
          const rotation = jitter(spec.rotationJitter, child, 'rotation');
          if (spec.orientToPath !== false) rotation[1] += Math.atan2(-at.tangent[0], -at.tangent[1]) * 180 / Math.PI;
          generatedPathSegments++;
          expand(spec.item, child, multiply(matrix, trs(position, rotation)), metadata, chain, { ...provenance, kind: 'path', subpath, distance }, trace);
        }
      });
      return;
    }
    const shape = paths(spec, id), points = shape.flatMap(s => s.points);
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (const [x, z] of points) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minZ = Math.min(minZ, z); maxZ = Math.max(maxZ, z); }
    const accepted = [], maxAttempts = spec.maxAttempts ?? Math.max(1, spec.count * 100);
    let attempts = 0;
    for (let i = 0; i < spec.count; i++) {
      const child = `${id}/scatter_${String(i).padStart(3, '0')}`, random = rng(seed, child, 'position'); let point;
      while (attempts < maxAttempts) {
        attempts++; const p = [minX + random() * (maxX - minX), minZ + random() * (maxZ - minZ)];
        if (contains(shape, p) && accepted.every(a => Math.hypot(a[0] - p[0], a[1] - p[1]) >= (spec.minSeparation || 0))) { point = p; accepted.push(p); break; }
      }
      if (!point) fail(id, 'maxAttempts', `placed ${i}/${spec.count} objects after ${maxAttempts} attempts; reduce count/minSeparation or enlarge region`);
      const rotation = jitter(spec.rotationJitter, child, 'rotation');
      if (spec.randomRotation) rotation[1] += rng(seed, child, 'yaw')() * 360;
      const range = spec.scaleRange || [1, 1], scale = range[0] + rng(seed, child, 'scale')() * (range[1] - range[0]);
      expand(spec.item, child, multiply(matrix, trs([point[0], 0, point[1]], rotation, scale)), metadata, chain, { ...provenance, kind: 'region', scatterIndex: i }, trace);
    }
  }
  world.instances.forEach((v, i) => { instance(v, `<world>/instances[${i}]`, true); expand(v, v.id, identity(), {}); });
  objects.sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  return canonical({ version: 1, id: world.id || options.worldId || 'world', name: world.name || options.worldName || world.id || options.worldId || 'World', seed, coordinates: { up: 'Y', pathPlane: 'XZ', assetForward: '-Z', angles: 'degrees', matrix: 'column-major; column vectors; parent * T * Rx * Ry * Rz * S' }, objects,
    stats: { objects: objects.length, definitionsUsed: used.size, generatedPathSegments } });
}
async function readJSON(filename) {
  let text;
  try { text = await fs.readFile(filename, 'utf8'); }
  catch (e) { throw new WorldError(filename, '<file>', 'file', e.message); }
  try { return JSON.parse(text); }
  catch (e) { throw new WorldError(filename, '<file>', 'JSON', e.message); }
}
async function loadWorld(filename) {
  const source = path.resolve(filename), world = await readJSON(source), registry = {}, origins = new Map();
  if (!object(world)) throw new WorldError(source, '<world>', 'world', 'expected a JSON object');
  if (own(world, 'definitionFiles') && (!Array.isArray(world.definitionFiles) || world.definitionFiles.some(p => typeof p !== 'string' || !p))) throw new WorldError(source, '<world>', 'definitionFiles', 'expected an array of JSON file paths');
  for (const relative of world.definitionFiles || []) {
    const filename = path.resolve(path.dirname(source), relative), document = await readJSON(filename);
    if (!object(document) || !object(document.definitions) || Object.keys(document).some(k => k !== 'definitions')) throw new WorldError(filename, '<registry>', 'definitions', 'expected {"definitions": {id: definition}}');
    for (const [id, spec] of Object.entries(document.definitions)) {
      if (own(registry, id)) throw new WorldError(filename, id, 'definition', 'duplicate definition ID');
      Object.defineProperty(registry, id, { value: spec, enumerable: true }); origins.set(id, filename);
    }
  }
  return { world, registry, options: { source, origins } };
}
async function compileFile(filename, options = {}) {
  const loaded = await loadWorld(filename), stem = path.basename(filename, '.json');
  const safeStem = stem.replace(/[^A-Za-z0-9_.:-]/g, '_') || 'world';
  const worldId = /^[A-Za-z0-9_]/.test(safeStem) ? safeStem : 'world_' + safeStem;
  return compileWorld(loaded.world, loaded.registry, { worldId, worldName: stem || 'World', ...loaded.options, ...options });
}
module.exports = { compileWorld, compileFile, loadWorld, merge, serialize, WorldError };
