'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { compileWorld, compileFile, merge, serialize, WorldError } = require('../tools/world/compiler');
const { flattenPath, sampleAt, contains } = require('../tools/world/path');
const { identity, multiply, trs } = require('../tools/world/transform');
const root = path.resolve(__dirname, '..'), cli = path.join(root, 'tools/build-world.js');
const model = (extra = {}) => ({ type: 'model', asset: 'fictional/box.glb', ...extra });
const world = (definitions, instances, extra = {}) => ({ version: 1, seed: 'test', definitions, instances, ...extra });
const close = (a, b, epsilon = 1e-8) => { assert.equal(a.length, b.length); a.forEach((v, i) => assert.ok(Math.abs(v - b[i]) < epsilon, `${v} != ${b[i]} at ${i}`)); };
const pathWorld = (svg, extra = {}) => world({ piece: model(), line: { type: 'path', path: svg, spacing: 5, item: { ref: 'piece' }, ...extra } }, [{ id: 'line', ref: 'line' }]);
const compile = w => compileWorld(w, {}, { source: 'fixture.json' });
const bad = (w, pattern) => assert.throws(() => compile(w), pattern);
const regionWorld = extra => world({ rock: model(), patch: { type: 'region', path: 'M0 0 L30 0 30 10 10 10 10 30 0 30Z', count: 30, minSeparation: 2, item: { ref: 'rock' }, ...extra } }, [{ id: 'patch', ref: 'patch' }]);

test('definitions resolve, root inheritance and overrides do not mutate source', () => {
  const w = world({ base: model({ position: [1, 0, 0], influences: { physical: { mass: 500, hp: 100 }, wind: { speed: 3 } } }), variant: { ref: 'base', scale: 2 } }, [
    { id: 'one', ref: 'variant', position: [4, 0, 0], influences: { physical: { hp: 75 } } }, { id: 'two', ref: 'base' },
  ]);
  const before = JSON.stringify(w), out = compile(w);
  assert.equal(JSON.stringify(w), before);
  close(out.objects[0].position, [4, 0, 0]); close(out.objects[0].scale, [2, 2, 2]);
  assert.equal(out.objects[0].source, 'variant'); assert.deepEqual(out.objects[0].provenance.references, ['base', 'variant']);
  assert.deepEqual(out.objects[0].influences, { physical: { hp: 75, mass: 500 }, wind: { speed: 3 } });
  assert.equal(out.objects[1].influences.physical.hp, 100); assert.equal(out.stats.definitionsUsed, 2);
});
test('override rules replace scalars, nulls and arrays; recursively merge objects', () => {
  assert.deepEqual(merge({ a: 1, list: [1, 2], children: [{ id: 'a' }], x: { a: 1, b: 2 } }, { a: null, list: [3], children: [], x: { b: 4 } }), { a: null, list: [3], children: [], x: { a: 1, b: 4 } });
  const w = world({ m: model(), g: { type: 'group', children: [{ id: 'old', ref: 'm' }] } }, [{ id: 'g', ref: 'g', children: [{ id: 'replacement', ref: 'm', asset: 'new.glb' }] }]);
  assert.deepEqual(compile(w).objects.map(o => [o.id, o.asset]), [['g/replacement', 'new.glb']]);
});
test('missing references and missing model assets give object/property diagnostics', () => {
  bad(world({}, [{ id: 'missing', ref: 'absent' }]), /fixture.json :: <world>\/instances\[0\] :: ref: missing reference 'absent'/);
  bad(world({ broken: { type: 'model' } }, []), /broken :: asset/);
  bad(world({ bad: { type: 'group', children: [{ id: 'child', ref: 'missing' }] } }, []), /missing reference/);
});
test('cycles include useful chains: inheritance, groups and generators', () => {
  bad(world({ a: { ref: 'b' }, b: { ref: 'a' } }, []), /a -> b -> a/);
  bad(world({ a: { type: 'group', children: [{ id: 'b', ref: 'b' }] }, b: { type: 'repeat', count: 1, offset: [0, 0, 0], item: { ref: 'a' } } }, []), /a -> b -> a/);
  bad(world({ a: { type: 'group', children: [] } }, [{ id: 'a', ref: 'a', children: [{ id: 'again', ref: 'a' }] }]), /cyclic reference/);
});
test('inheritance provenance is separate from actual expansion ancestry', () => {
  const out = compile(world({ a: { type: 'group', children: [] }, m: model(), b: { ref: 'a', children: [{ id: 'empty', ref: 'a' }, { id: 'm', ref: 'm' }] } }, [{ id: 'b', ref: 'b' }]));
  assert.equal(out.objects.length, 1); assert.deepEqual(out.objects[0].provenance.references, ['a', 'b', 'm']);
});
test('asset paths are symbolic; selection single uses the first candidate', () => {
  const out = compile(world({ m: model({ asset: { selection: 'single', items: [{ path: 'never/exists/a.glb' }, { path: 'b.glb' }] } }) }, [{ id: 'm', ref: 'm' }]));
  assert.equal(out.objects[0].asset, 'never/exists/a.glb');
});
function choices(selection, seed = 31) {
  return world({ m: model({ asset: { selection, items: [{ path: 'a.glb', weight: 1 }, { path: 'b.glb', weight: 9 }, { path: 'never.glb', weight: 0 }] } }) }, Array.from({ length: 200 }, (_, i) => ({ id: `item_${i}`, ref: 'm' })), { seed });
}
test('weighted selection is deterministic, respects weights and zero weight', () => {
  const w = choices('weighted'), a = compile(w), b = compile(w);
  assert.equal(serialize(a), serialize(b));
  const bs = a.objects.filter(o => o.asset === 'b.glb').length;
  assert.ok(bs > 160 && bs < 199, `${bs} weighted selections`); assert.ok(!a.objects.some(o => o.asset === 'never.glb'));
  assert.notDeepEqual(a.objects, compile(choices('weighted', 32)).objects);
});
test('uniform random selection can choose every candidate', () => {
  const out = compile(choices('random')); assert.equal(new Set(out.objects.map(o => o.asset)).size, 3);
});
test('unrelated objects, input order and definition order do not reshuffle choices', () => {
  const w = choices('weighted'); const before = compile(w);
  w.definitions.unrelated = model({ asset: 'other.glb' }); w.instances.unshift({ id: 'elsewhere', ref: 'unrelated' }); w.instances.reverse();
  const after = compile(w); assert.deepEqual(before.objects, after.objects.filter(o => o.id !== 'elsewhere'));
  w.definitions = Object.fromEntries(Object.entries(w.definitions).reverse()); assert.equal(serialize(after), serialize(compile(w)));
});
test('candidate rotation and scale compose after instance transforms', () => {
  const out = compile(world({ m: model({ scale: 2, rotation: [0, 90, 0], asset: { selection: 'single', items: [{ path: 'a.glb', rotation: [0, 90, 0], scale: [.5, 1, 2] }] } }) }, [{ id: 'm', ref: 'm' }]));
  close(out.objects[0].scale, [1, 2, 4]); const m = out.objects[0].transform;
  close([-m[8] / 4, -m[9] / 4, -m[10] / 4], [0, 0, 1]);
});
test('straight path uses fixed arc distance and -Z tangent orientation', () => {
  const out = compile(pathWorld('M0 0 L20 0'));
  assert.deepEqual(out.objects.map(o => o.position), [[0, 0, 0], [5, 0, 0], [10, 0, 0], [15, 0, 0], [20, 0, 0]]);
  close(out.objects[2].transform.slice(8, 11), [-1, 0, 0]); assert.equal(out.stats.generatedPathSegments, 5);
});
test('spacing/overlap overrides determine step; no forced short final interval', () => {
  const w = pathWorld('M0 0 L11 0', { spacing: 5, overlap: 1 });
  assert.deepEqual(compile(w).objects.map(o => o.position[0]), [0, 4, 8]);
  w.instances[0].spacing = 3; w.instances[0].overlap = 0;
  assert.deepEqual(compile(w).objects.map(o => o.position[0]), [0, 3, 6, 9]);
});
test('closed paths exclude duplicate endpoints and multiple subpaths remain separate', () => {
  const closed = compile(pathWorld('M0 0 H10 V10 H0 Z', { spacing: 10 }));
  assert.equal(closed.objects.length, 4); assert.equal(new Set(closed.objects.map(o => o.position.join(','))).size, 4);
  const multi = compile(pathWorld('M0 0 L10 0 M100 0 l10 0'));
  assert.deepEqual(multi.objects.map(o => o.position[0]), [0, 5, 10, 100, 105, 110]);
});
test('C/S reflection follows SVG semantics and resets after lines/moves', () => {
  const smooth = flattenPath('M0 0 C10 0 10 10 20 10 S30 20 40 0', 64);
  const explicit = flattenPath('M0 0 C10 0 10 10 20 10 C30 10 30 20 40 0', 64);
  assert.deepEqual(smooth, explicit);
  assert.deepEqual(flattenPath('M0 0 L10 0 S20 10 30 0'), flattenPath('M0 0 L10 0 C10 0 20 10 30 0'));
  assert.deepEqual(flattenPath('M0 0 C1 2 3 4 5 6 M10 10 S20 20 30 10'), flattenPath('M0 0 C1 2 3 4 5 6 M10 10 C10 10 20 20 30 10'));
});
test('relative M/L/H/V/C/S/Z, implicit moveto lines and numeric syntax', () => {
  assert.deepEqual(flattenPath('M10 20 l10 0 h5 v5 c5 0 5 10 10 10 s5 -10 10 -10 z'), flattenPath('M10 20 L20 20 H25 V25 C30 25 30 35 35 35 S40 25 45 25 Z'));
  assert.deepEqual(flattenPath('m1 2 3 4 5 6')[0].points, [[1, 2], [4, 6], [9, 12]]);
  assert.deepEqual(flattenPath('M1e1,-2e0L.5,+3.25')[0].points, [[10, -2], [.5, 3.25]]);
});
test('curve sampling is approximately uniform in arc length, not parameter t', () => {
  const shape = flattenPath('M0 0 C0 80 80 80 80 0', 256)[0];
  const samples = Array.from({ length: Math.floor(shape.length / 4) }, (_, i) => sampleAt(shape, i * 4).point);
  const gaps = samples.slice(1).map((p, i) => Math.hypot(p[0] - samples[i][0], p[1] - samples[i][1]));
  assert.ok(Math.min(...gaps) > 3.97 && Math.max(...gaps) <= 4.000001);
  close(sampleAt(shape, shape.length).point, [80, 0]);
});
test('path jitter is bounded/deterministic and does not affect asset choice', () => {
  const w = pathWorld('M0 0 L20 0', { positionJitter: [.25, .5, .75], rotationJitter: [2, 10, 2] });
  const out = compile(w); assert.equal(serialize(out), serialize(compile(w)));
  out.objects.forEach((o, i) => { assert.ok(Math.abs(o.position[0] - i * 5) <= .25); assert.ok(Math.abs(o.position[1]) <= .5 && Math.abs(o.position[2]) <= .75); });
  const assets = out.objects.map(o => o.asset); delete w.definitions.line.positionJitter;
  assert.deepEqual(compile(w).objects.map(o => o.asset), assets);
});
test('nested groups compose translation, rotations and scale in documented order', () => {
  const w = world({ m: model(), inner: { type: 'group', children: [{ id: 'm', ref: 'm', position: [0, 0, -2] }] }, outer: { type: 'group', position: [10, 0, 0], rotation: [0, 90, 0], scale: 2, children: [{ id: 'inner', ref: 'inner' }] } }, [{ id: 'village', ref: 'outer' }]);
  const o = compile(w).objects[0]; close(o.position, [6, 0, 0]); close(o.scale, [2, 2, 2]); assert.equal(o.id, 'village/inner/m');
  close(multiply(identity(), trs([0, 0, 0], [90, 0, 0])).slice(8, 11), [0, -1, 0]);
});
test('nonuniform nested rotation retains shear in authoritative matrix', () => {
  const w = world({ m: model({ rotation: [0, 45, 0] }), g: { type: 'group', scale: [2, 1, 1], children: [{ id: 'm', ref: 'm' }] } }, [{ id: 'g', ref: 'g' }]);
  const o = compile(w).objects[0], m = o.transform;
  assert.ok(Math.abs(m[0] * m[8] + m[1] * m[9] + m[2] * m[10]) > 1);
  close(o.scale, [Math.sqrt(2.5), 1, Math.sqrt(2.5)]);
});
test('repeated groups have unique IDs, local offsets, no doubled default transforms', () => {
  const w = world({ m: model(), car: { type: 'group', position: [2, 0, 0], children: [{ id: 'body', ref: 'm' }] } }, [{ id: 'cars', ref: 'car', rotation: [0, 90, 0], repeat: { count: 3, offset: [0, 0, -12] } }]);
  const out = compile(w); assert.equal(out.objects.length, 3);
  out.objects.forEach((o, i) => { assert.equal(o.id, `cars/repeat_00${i}/body`); close(o.position, [2 - i * 12, 0, 0]); });
  const repeated = compile(world({ m: model({ position: [2, 0, 0] }), r: { type: 'repeat', position: [10, 0, 0], count: 3, offset: [3, 0, 0], item: { ref: 'm' } } }, [{ id: 'r', ref: 'r' }]));
  assert.deepEqual(repeated.objects.map(o => o.position[0]), [12, 15, 18]);
});
test('generated paths/regions inherit nested transforms', () => {
  const w = pathWorld('M0 0 L10 0'); w.instances[0].position = [4, 2, 7]; w.instances[0].rotation = [0, 90, 0];
  const out = compile(w); close(out.objects[1].position, [4, 2, 2]); close(out.objects[1].transform.slice(8, 11), [0, 0, 1]);
  const region = regionWorld({ count: 1 }); const origin = compile(region).objects[0].position;
  region.instances[0].position = [100, 5, 200]; close(compile(region).objects[0].position, [100 + origin[0], 5, 200 + origin[2]]);
});
test('scatter stays inside nonrectangular regions with minimum separation', () => {
  const w = regionWorld(), out = compile(w), shape = flattenPath(w.definitions.patch.path);
  assert.equal(out.objects.length, 30);
  for (let i = 0; i < out.objects.length; i++) {
    const a = out.objects[i].position; assert.ok(contains(shape, [a[0], a[2]]));
    for (let j = 0; j < i; j++) { const b = out.objects[j].position; assert.ok(Math.hypot(a[0] - b[0], a[2] - b[2]) >= 2); }
  }
  assert.equal(serialize(out), serialize(compile(w)));
});
test('closed curved regions, even-odd holes and disjoint subpaths', () => {
  const w = regionWorld({ path: 'M0 0 C0 -10 30 -10 30 0 L30 30 H0 Z M10 10H20V20H10Z M50 0H60V10H50Z', count: 60, minSeparation: .5 });
  const out = compile(w), shape = flattenPath(w.definitions.patch.path);
  assert.ok(!contains(shape, [15, 15])); assert.ok(contains(shape, [55, 5]));
  assert.ok(out.objects.every(o => contains(shape, [o.position[0], o.position[2]])));
});
test('scatter rotation/scale variations, boundary and friction overrides', () => {
  const w = regionWorld({ count: 10, randomRotation: true, scaleRange: [.5, 1.5], influences: { physical: { friction: .8, hp: 40 }, movement: { tractionMultiplier: .7 } } });
  w.instances[0].path = 'M100 100 H140 V140 H100 Z'; w.instances[0].influences = { physical: { friction: .2 } };
  const out = compile(w);
  out.objects.forEach(o => { assert.ok(o.position[0] >= 100 && o.position[2] >= 100); assert.ok(o.scale.every(s => s >= .5 && s <= 1.5)); assert.equal(o.influences.physical.friction, .2); assert.equal(o.influences.physical.hp, 40); assert.equal(o.influences.movement.tractionMultiplier, .7); });
});
test('scatter attempt cap fails explicitly rather than silently placing fewer objects', () => {
  bad(regionWorld({ path: 'M0 0H1V1H0Z', count: 3, minSeparation: 10, maxAttempts: 12 }), /maxAttempts: placed 1\/3 objects after 12 attempts/);
  bad(regionWorld({ path: 'M0 0L10 0L10 10', count: 1 }), /explicitly closed/);
});
test('influences inherit recursively; explicit leaf properties win; extensions survive', () => {
  const w = world({ m: model({ influences: { physical: { mass: 100 }, movement: { collision: 'solid' } } }), g: { type: 'group', influences: { physical: { friction: .8, movable: false }, wind: { velocity: [1, 0, 0], gusts: { amount: 2 } } }, children: [{ id: 'm', ref: 'm', influences: { physical: { friction: .3 } } }] } }, [{ id: 'g', ref: 'g' }]);
  assert.deepEqual(compile(w).objects[0].influences, { physical: { friction: .3, mass: 100, movable: false }, movement: { collision: 'solid' }, wind: { gusts: { amount: 2 }, velocity: [1, 0, 0] } });
  const hp = compile(world({ m: model({ influences: { physical: { hp: 0 } } }) }, [{ id: 'm', ref: 'm' }])).objects[0].influences.physical;
  assert.deepEqual(hp, { hp: 0 }); // No implicit indestructibility.
});
test('invalid influences, assets, numeric properties and unknown keys fail validation', () => {
  for (const extra of [
    { influences: { physical: { mass: -1 } } }, { influences: { physical: { movable: 'yes' } } }, { influences: { physical: { hp: -1 } } },
    { influences: { physical: { destructible: true, indestructible: true } } }, { influences: { movement: { tractionMultiplier: -1 } } },
    { influences: { water: 2 } }, { position: [1, 2] }, { scale: 0 }, { rotation: [0, Infinity, 0] }, { typo: 2 },
    { asset: 'a.fbx' }, { asset: { selection: 'other', items: [{ path: 'a.glb' }] } },
    { asset: { selection: 'weighted', items: [{ path: 'a.glb', weight: 0 }] } }, { asset: { selection: 'weighted', items: [{ path: 'a.glb', weight: -1 }] } },
    { asset: { selection: 'random', items: [] } },
  ]) bad(world({ m: model(extra) }, []), /fixture.json/);
  bad(pathWorld('M0 0 L10 0', { spacing: 0 }), /spacing/); bad(pathWorld('M0 0L10 0', { overlap: 5 }), /overlap/);
  bad(regionWorld({ count: -1 }), /count/); bad(regionWorld({ scaleRange: [2, 1] }), /scaleRange/);
});
test('invalid SVG is rejected clearly, including unused definitions', () => {
  for (const [source, pattern] of [['M0 0 Q1 2 3 4', /unsupported SVG command 'Q'/], ['M0 0 A1 1 0 0 0 2 2', /unsupported SVG/], ['L0 0', /begin with M/], ['M0 0 C1 2', /missing coordinates/], ['M0 0 @', /invalid SVG token/], ['M0 0 L', /missing coordinates/], ['M0 0', /nonzero drawable/]]) bad(pathWorld(source), pattern);
});
test('duplicate IDs, excessive expansion, unsafe JSON keys and invalid world schema', () => {
  bad(world({ m: model() }, [{ id: 'a', ref: 'm' }, { id: 'a', ref: 'm' }]), /duplicate hierarchical/);
  bad(world({ m: model() }, [{ id: 'bad/id', ref: 'm' }]), /expected a nonempty ID/);
  bad(world({ m: model(), g: { type: 'group', children: [{ id: 'a', ref: 'm' }, { id: 'a', ref: 'm' }] } }, []), /duplicate child/);
  assert.throws(() => compileWorld(pathWorld('M0 0L100 0'), {}, { maxObjects: 2 }), /output exceeds 2/);
  bad(world({ m: model() }, [{ id: 'm', ref: 'm', repeat: { count: 1e9, offset: [0, 0, 0] } }]), /repeat.count/);
  bad(JSON.parse('{"version":1,"definitions":{"__proto__":{"type":"model","asset":"x.glb"}},"instances":[]}'), /unsafe JSON key/);
  assert.equal({}.asset, undefined);
  bad({ version: 2, instances: [] }, /version/); bad({ version: 1, instances: [], seed: {} }, /seed/);
});
test('empty repeats are valid and provenance can be disabled', () => {
  const w = world({ m: model() }, [{ id: 'm', ref: 'm', repeat: { count: 0, offset: [0, 0, 0] } }]);
  assert.equal(compile(w).objects.length, 0); delete w.instances[0].repeat;
  assert.equal(compileWorld(w, {}, { provenance: false }).objects[0].provenance, undefined);
});
test('sample world is deterministic, complete and requires no GLB files', async () => {
  const a = await compileFile(path.join(root, 'worlds/example.json')), b = await compileFile(path.join(root, 'worlds/example.json'));
  assert.equal(serialize(a), serialize(b)); assert.ok(a.objects.length > 100); assert.equal(new Set(a.objects.map(o => o.id)).size, a.objects.length);
  assert.ok(a.stats.definitionsUsed >= 16 && a.stats.generatedPathSegments > 40);
  assert.equal(a.objects.filter(o => /train_yard\/cars\/repeat_\d+\/frame$/.test(o.id)).length, 5);
  assert.ok(a.objects.some(o => o.id === 'station_house/building' && /weathered/.test(o.asset)));
  assert.ok(a.objects.filter(o => o.id.startsWith('wet_rocks/')).every(o => o.influences.physical.friction === .3));
});
test('CLI builds/validates, reports counts, resolves files relative to world and handles errors', async t => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-world-')); t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const source = path.join(root, 'worlds/example.json'), output = path.join(temp, 'nested/world.json');
  const run = args => { const result = spawnSync(process.execPath, [cli, ...args], { cwd: temp, encoding: 'utf8' }); assert.ifError(result.error); return result; };
  let result = run([source, '--validate']); assert.equal(result.status, 0, result.stderr); assert.match(result.stdout, /objects, 18 definitions used, \d+ generated path segments/); assert.deepEqual(await fs.readdir(temp), []);
  result = run([source, '--output', output]); assert.equal(result.status, 0, result.stderr); const bytes = await fs.readFile(output, 'utf8');
  assert.equal(bytes, serialize(await compileFile(source))); result = run([source, '--output', output]); assert.equal(result.status, 0); assert.equal(await fs.readFile(output, 'utf8'), bytes);
  result = run([source, '--validate', '--output', output]); assert.notEqual(result.status, 0); assert.match(result.stderr, /validation writes no files/);
  result = run([source, '--output', source]); assert.notEqual(result.status, 0); assert.match(result.stderr, /overwrite/);
  const badFile = path.join(temp, 'bad.json'); await fs.writeFile(badFile, '{bad json');
  result = run([badFile, '--validate']); assert.notEqual(result.status, 0); assert.match(result.stderr, /bad.json.*JSON/);
  result = run([path.join(temp, 'missing.json'), '--validate']); assert.notEqual(result.status, 0); assert.match(result.stderr, /missing.json.*file/);
  assert.equal(run(['--help']).status, 0); assert.notEqual(run([source, '--bogus']).status, 0);
});
test('external duplicate definitions and bad registry definitions identify their source files', async t => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-world-defs-')); t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const source = path.join(temp, 'world.json'), registry = path.join(temp, 'assets.json');
  await fs.writeFile(registry, JSON.stringify({ definitions: { bad: model({ asset: 'wrong.fbx' }) } }));
  await fs.writeFile(source, JSON.stringify({ version: 1, definitionFiles: ['assets.json'], instances: [] }));
  await assert.rejects(compileFile(source), e => e instanceof WorldError && e.file === registry && e.id === 'bad' && e.property === 'asset');
  await fs.writeFile(registry, JSON.stringify({ definitions: { m: model() } }));
  await fs.writeFile(source, JSON.stringify({ version: 1, definitionFiles: ['assets.json', 'assets.json'], instances: [] }));
  await assert.rejects(compileFile(source), /duplicate definition ID/);
});

test('region placements and random selections are stable when unrelated objects are added', () => {
  const w = regionWorld({ randomRotation: true, scaleRange: [.5, 2] }), before = compile(w);
  w.definitions.extra = model(); w.instances.unshift({ id: 'extra', ref: 'extra' });
  assert.deepEqual(compile(w).objects.filter(o => o.id.startsWith('patch/')), before.objects);
});
test('Studio catalog discovers manifests, includes built-in arena and marks symbolic worlds preview-only', async t => {
  const { registerWorlds, discoverWorlds } = require('../tools/world/catalog');
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-catalog-')); t.after(() => fs.rm(temp, { recursive: true, force: true }));
  for (const id of ['forest', 'village']) {
    const w = world({ m: model() }, [{ id: 'm', ref: 'm' }], { id, name: `${id} arena` });
    await fs.writeFile(path.join(temp, `${id}.json`), serialize(compile(w)));
  }
  const output = path.join(temp, 'catalog.model.json'), catalog = await registerWorlds(temp, output);
  const fields = node => Object.fromEntries(node.Children.map(c => [c.Name, c.Properties.Value]));
  assert.equal(catalog.Children.length, 3); assert.equal(fields(catalog.Children[0]).WorldId, 'default');
  for (const entry of catalog.Children.slice(1)) { const v = fields(entry); assert.equal(v.Status, 'preview-only'); assert.match(v.Reason, /no Roblox asset mapping/); assert.equal(v.AssetCount, 1); }
  assert.equal(await fs.readFile(output, 'utf8'), serialize(await discoverWorlds(temp)));
  await fs.copyFile(path.join(temp, 'forest.json'), path.join(temp, 'duplicate.json'));
  await assert.rejects(discoverWorlds(temp), /duplicate\/reserved world ID/);
});
test('Studio catalog CLI and checked-in sample catalog match compiled manifests', async t => {
  const { discoverWorlds } = require('../tools/world/catalog');
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-register-cli-')); t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const manifest = await compileFile(path.join(root, 'worlds/example.json'));
  await fs.writeFile(path.join(temp, 'example.json'), serialize(manifest));
  const output = path.join(temp, 'studio.model.json');
  const result = spawnSync(process.execPath, [path.join(root, 'tools/register-worlds.js'), temp, '--output', output], { encoding: 'utf8' });
  assert.ifError(result.error); assert.equal(result.status, 0, result.stderr); assert.match(result.stdout, /1 built-in ready, 1 preview-only/);
  const expected = await discoverWorlds(temp); assert.equal(await fs.readFile(output, 'utf8'), serialize(expected));
  const sourceCatalog = JSON.parse(await fs.readFile(path.join(root, 'worlds/studio-worlds.model.json'), 'utf8'));
  assert.equal(sourceCatalog.Children.length, 3);
  const village = sourceCatalog.Children.find(c => c.Name === 'village_battle'), fields = Object.fromEntries(village.Children.map(c => [c.Name, c.Properties.Value]));
  assert.equal(fields.WorldId, manifest.id); assert.equal(fields.DisplayName, manifest.name); assert.equal(fields.ObjectCount, manifest.objects.length);
  const project = JSON.parse(await fs.readFile(path.join(root, 'default.project.json'), 'utf8'));
  const selected = project.tree.ServerStorage.BattleWorksStudio.SelectedWorld;
  assert.equal(selected.$className, 'StringValue'); assert.ok(!Object.hasOwn(selected.$properties || {}, 'Value'), 'Rojo does not own/reset the Studio-selected Value');
});

test('manifest identity defaults handle filenames with spaces; explicit null seed is invalid', async t => {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-world-name-')); t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const file = path.join(temp, 'forest arena.json'); await fs.writeFile(file, JSON.stringify(world({ m: model() }, [{ id: 'm', ref: 'm' }])));
  const out = await compileFile(file); assert.equal(out.id, 'forest_arena'); assert.equal(out.name, 'forest arena');
  bad(world({}, [], { seed: null }), /seed/);
});
test('catalog rejects malformed manifests and accepts uppercase GLB extensions', async t => {
  const { discoverWorlds } = require('../tools/world/catalog');
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-catalog-validation-')); t.after(() => fs.rm(temp, { recursive: true, force: true }));
  const file = path.join(temp, 'world.json'); await fs.writeFile(file, 'null');
  await assert.rejects(discoverWorlds(temp), /world.json: expected a compiled/);
  await fs.writeFile(file, JSON.stringify({ version: 1, id: 3, objects: [] })); await assert.rejects(discoverWorlds(temp), /invalid world id/);
  await fs.writeFile(file, serialize(compile(world({ m: model({ asset: 'fictional/BOX.GLB' }) }, [{ id: 'm', ref: 'm' }], { id: 'upper' }))));
  assert.equal((await discoverWorlds(temp)).Children.length, 2);
});

test('single-tree asset binding resolves logical ID and source path independently from placement', async () => {
  const { resolveAsset, studioPlacement } = require('../tools/world/studio-placement');
  const { trs } = require('../tools/world/transform');
  const bindings = JSON.parse(await fs.readFile(path.join(root, 'worlds/roblox-assets.json'), 'utf8'));
  assert.deepEqual(resolveAsset('tree_large', bindings), resolveAsset('GLBs/suburban/tree-large.glb', bindings));
  assert.equal(resolveAsset('missing.glb', bindings), null);
  const configured = JSON.parse(await fs.readFile(path.join(root, 'worlds/tree-test.json'), 'utf8')).instances[0];
  const manifest = await compileFile(path.join(root, 'worlds/tree-test.json'));
  manifest.objects = manifest.objects.filter(o => o.id === 'tree-large');
  assert.equal(manifest.objects.length, 1); assert.equal(manifest.objects[0].asset, 'GLBs/suburban/tree-large.glb');
  const placement = studioPlacement(manifest, bindings);
  assert.equal(placement.id, 'tree-large'); assert.equal(placement.model, 'tree-large'); assert.equal(placement.scale, 45);
  close(placement.position, configured.position);
  close(trs(placement.position, placement.rotation, placement.scale), manifest.objects[0].transform);
  assert.equal(studioPlacement(manifest, {}), null);
  for (const angles of [[10, 35, 20], [0, 90, 0], [20, -90, 10]]) {
    const changed = structuredClone(manifest); changed.objects[0].influences = {}; changed.objects[0].transform = trs([2, 0, -3], angles, 2);
    const p = studioPlacement(changed, bindings);
    close(trs(p.position, p.rotation, p.scale), changed.objects[0].transform);
  }
  const nonuniform = structuredClone(manifest); nonuniform.objects[0].transform = trs([0, 0, 0], [0, 0, 0], [1, 2, 1]);
  assert.equal(studioPlacement(nonuniform, bindings), null, 'unsupported nonuniform model placement remains preview-only');
});


test('imported tree supports fixed solid durability and precise unsupported-profile diagnostics', async () => {
  const { studioPlacement, placementIssue, interactionFor } = require('../tools/world/studio-placement');
  const bindings = JSON.parse(await fs.readFile(path.join(root, 'worlds/roblox-assets.json'), 'utf8'));
  const manifest = await compileFile(path.join(root, 'worlds/tree-test.json'));
  manifest.objects = manifest.objects.filter(o => o.id === 'tree-large');
  const p = studioPlacement(manifest, bindings);
  assert.equal(p.interaction.solid, true);
  assert.equal(p.interaction.destructible, true);
  assert.equal(p.interaction.hp, 150);
  assert.equal(placementIssue(manifest, bindings), null);
  const binding = { id: 'tree', collider: bindings.tree_large.collider };
  assert.equal(interactionFor({physical:{indestructible:true,hp:0},movement:{collision:'solid'}},binding).destructible,false);
  assert.equal(interactionFor({},binding),null);
  for (const [influences,pattern] of [
    [{physical:{movable:true}},/pushing and tipping/],
    [{physical:{mass:100}},/physical.mass/],
    [{movement:{tractionMultiplier:0.7}},/movement.tractionMultiplier/],
    [{physical:{destructible:true,indestructible:true}},/Conflicting/],
    [{movement:{collision:'solid',traversable:true}},/contradicts/],
    [{physical:{hp:-1}},/nonnegative/],
  ]) {
    const m = structuredClone(manifest); m.objects[0].influences = influences;
    assert.match(placementIssue(m,bindings),pattern);
    assert.equal(studioPlacement(m,bindings),null);
  }
  assert.throws(()=>interactionFor({movement:{collision:'solid'}},{id:'missing'}),/requires collider/);
  assert.match(placementIssue(manifest,{}),/no Roblox asset mapping/);
  const { trs } = require('../tools/world/transform');
  for (const yaw of [90,135,180,270]) {
    const m = structuredClone(manifest); m.objects[0].transform = trs([0,0,0],[0,yaw,0],45);
    const q = studioPlacement(m,bindings);
    close(trs(q.position,q.rotation,q.scale),m.objects[0].transform);
  }
  const tilted = structuredClone(manifest); tilted.objects[0].transform=trs([0,0,0],[10,0,0],45);
  assert.match(placementIssue(tilted,bindings),/upright/);
});


test('tree test compiles a curved closed fence and registers every native placement', async () => {
  const { studioPlacements, placementIssue } = require('../tools/world/studio-placement');
  const bindings = JSON.parse(await fs.readFile(path.join(root,'worlds/roblox-assets.json'),'utf8'));
  const manifest = await compileFile(path.join(root,'worlds/tree-test.json'));
  const panels = manifest.objects.filter(o=>o.asset==='GLBs/forest/fence.glb');
  assert.ok(panels.length>=8);
  assert.equal(manifest.objects.filter(o=>o.asset.endsWith('tree-large.glb')).length,1);
  assert.equal(new Set(panels.map(o=>o.id)).size,panels.length);
  assert.ok(new Set(panels.map(o=>o.transform[0].toFixed(4))).size>=6,'panels follow changing path tangents');
  assert.ok(panels.every(o=>Math.hypot(o.position[0],o.position[2])>45),'fence surrounds central tree');
  assert.equal(placementIssue(manifest,bindings),null);
  const placements=studioPlacements(manifest,bindings);
  assert.equal(placements.length,manifest.objects.length);
  const definitions=JSON.parse(await fs.readFile(path.join(root,'worlds/definitions/kenney.json'),'utf8')).definitions;
  const panelScale=45*(definitions.rope_fence.item.scale ?? 1);
  assert.ok(placements.every(p=>Math.abs(p.scale-(p.model==='rope-fence'?panelScale:45))<1e-8),'world assetScale composes with configured panel multiplier');
  const panel=placements.find(p=>p.model==='rope-fence');
  assert.equal(panel.interaction.solid,true,'fence blocks tanks');
  assert.equal(panel.interaction.destructible,false,'fence remains indestructible as configured');
  assert.deepEqual(panel.interaction.collider,{widthFraction:1,depthFraction:1,heightFraction:1});
  assert.equal(placements.filter(p=>p.model==='rope-fence').length,panels.length);
  const { discoverWorlds }=require('../tools/world/catalog');
  const dir=await fs.mkdtemp(path.join(require('node:os').tmpdir(),'bw-fence-'));
  try {
    await fs.writeFile(path.join(dir,'tree.json'),JSON.stringify(manifest));
    const catalog=await discoverWorlds(dir,bindings);
    const entry=catalog.Children.find(e=>e.Name==='tree_test');
    assert.equal(entry.Children.find(e=>e.Name==='Status').Properties.Value,'asset-dependent');
    assert.equal(entry.Children.find(e=>e.Name==='Placements').Children.length,placements.length);
  } finally { await fs.rm(dir,{recursive:true,force:true}); }
  const noFence={...bindings};delete noFence.fence_section;
  assert.match(placementIssue(manifest,noFence),/rope-fence.*fence.glb.*no Roblox asset mapping/);
  assert.equal(studioPlacements(manifest,noFence),null,'missing binding rejects whole world');
});


test('world assetScale sizes models exactly once without scaling layout or path spacing', () => {
  const w=world({m:model(),g:{type:'group',position:[20,0,0],children:[{id:'child',ref:'m',position:[3,0,0],scale:2}]},p:{type:'path',path:'M0 0 L20 0',spacing:10,item:{ref:'m'}}},[{id:'g',ref:'g'},{id:'p',ref:'p'}]);
  const original=compile(w); w.assetScale=45; const scaled=compile(w);
  assert.equal(scaled.objects.length,original.objects.length);
  for (let i=0;i<scaled.objects.length;i++) {
    close(scaled.objects[i].position,original.objects[i].position);
    close(scaled.objects[i].scale,original.objects[i].scale.map(n=>n*45));
  }
  for (const n of [0,-1,'45',null,Infinity]) {w.assetScale=n;assert.throws(()=>compile(w),/assetScale/);}
});
