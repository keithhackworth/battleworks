
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { validateAssets, buildPlace } = require('../tools/roblox-assets');
const ROOT = path.resolve(__dirname, '..');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function run(command, args) {
 const result = spawnSync(command, args, { encoding: 'utf8' });
 assert.ifError(result.error); return result;
}
// Synthetic native Roblox data, not a substitute tree shipped in assets/.
const MODEL_XML = '<roblox version="4">\n<Item class="Model" referent="RBX0"><Properties>\n<string name="Name">tree-large</string>\n<Ref name="PrimaryPart">RBX1</Ref>\n<float name="ScaleFactor">1.5</float>\n</Properties>\n<Item class="Model" referent="RBX2"><Properties><string name="Name">TrunkGroup</string></Properties>\n<Item class="MeshPart" referent="RBX1"><Properties>\n<string name="Name">Trunk</string>\n<Content name="MeshId"><url>rbxassetid://123456</url></Content>\n<Content name="TextureID"><url>rbxassetid://234567</url></Content>\n<Vector3 name="size"><X>2</X><Y>12</Y><Z>3</Z></Vector3>\n<CoordinateFrame name="CFrame"><X>3</X><Y>6</Y><Z>-2</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>\n<CoordinateFrame name="PivotOffset"><X>0</X><Y>-6</Y><Z>0</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>\n</Properties>\n<Item class="SurfaceAppearance" referent="RBX3"><Properties><string name="Name">Bark</string><Content name="ColorMap"><url>rbxassetid://345678</url></Content></Properties></Item>\n</Item></Item></Item></roblox>\n';
async function fixture(t) {
 const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-persistent-model-'));
 t.after(() => fs.rm(directory, { recursive: true, force: true }));
 await fs.mkdir(path.join(directory, 'models'));
 const projectFile = path.join(directory, 'default.project.json'), bindingsFile = path.join(directory, 'bindings.json');
 await fs.writeFile(projectFile, JSON.stringify({ name: 'PersistenceFixture', tree: { $className: 'DataModel', ServerStorage: { $className: 'ServerStorage', BattleWorksAssets: { $path: 'models', $ignoreUnknownInstances: true } } } }));
 await fs.writeFile(bindingsFile, JSON.stringify({ tree_large: { source: 'GLBs/suburban/tree-large.glb', model: 'tree-large' } }));
 return { directory, projectFile, bindingsFile };
}
function assertProperties(xml) {
 assert.match(xml, /name="Mesh(?:Id|Content)"/); assert.match(xml, /rbxassetid:\/\/123456/);
 assert.match(xml, /name="Texture(?:ID|Content)"/); assert.match(xml, /rbxassetid:\/\/234567/);
 assert.match(xml, /name="ColorMap(?:Content)?"/); assert.match(xml, /rbxassetid:\/\/345678/);
 assert.match(xml, /<float name="ScaleFactor">1.5<\/float>/);
 assert.match(xml, /<string name="Name">TrunkGroup<\/string>/);
 assert.match(xml, /<CoordinateFrame name="PivotOffset">\s*<X>0<\/X>\s*<Y>-6<\/Y>/);
 assert.match(xml, /<CoordinateFrame name="CFrame">\s*<X>3<\/X>\s*<Y>6<\/Y>\s*<Z>-2<\/Z>/);
 assert.match(xml, /<Vector3 name="size">\s*<X>2<\/X>\s*<Y>12<\/Y>\s*<Z>3<\/Z>/);
 const mesh = xml.match(/<Item class="MeshPart" referent="([^"]+)"/);
 assert.ok(mesh); assert.ok(xml.includes(`<Ref name="PrimaryPart">${mesh[1]}</Ref>`));
}
for (const extension of ['rbxmx', 'rbxm']) test(`Rojo packages ${extension} models with native hierarchy, references, pivot and scale`, async t => {
 const f = await fixture(t), input = path.join(f.directory, 'source.rbxmx');
 await fs.writeFile(input, MODEL_XML);
 const source = path.join(f.directory, `models/tree-large.${extension}`);
 if (extension === 'rbxmx') await fs.copyFile(input, source);
 else {
  const modelProject = path.join(f.directory, 'native.project.json');
  await fs.writeFile(modelProject, JSON.stringify({ name: 'BinaryFixture', tree: { $path: 'source.rbxmx' } }));
  const result = run('rojo', ['build', modelProject, '-o', source]); assert.equal(result.status, 0, result.stderr);
 }
 const before = hash(await fs.readFile(source));
 const validation = await validateAssets(f); assert.equal(validation.models, 1); assert.deepEqual(validation.missing, []);
 const output = path.join(f.directory, 'build/game.rbxlx');
 await buildPlace({ ...f, output }); assertProperties(await fs.readFile(output, 'utf8'));
 assert.equal(hash(await fs.readFile(source)), before, 'build does not rewrite the source model');
 // A second clean build needs no GLB, editor or previous generated place.
 await fs.rm(output); await buildPlace({ ...f, output }); assertProperties(await fs.readFile(output, 'utf8'));
 const binary = path.join(f.directory, 'build/game.rbxl'); await buildPlace({ ...f, output: binary });
 assert.ok((await fs.stat(binary)).size > 100);
});
test('missing exports fail before an existing place or Studio backup can be replaced', async t => {
 const f = await fixture(t), output = path.join(f.directory, 'existing-place.rbxl');
 const backup = Buffer.from('KEEP EXISTING IMPORTED STUDIO DATA'); await fs.writeFile(output, backup);
 await assert.rejects(buildPlace({ ...f, output }), /Persistent asset exports missing.*\ntree_large:/);
 assert.deepEqual(await fs.readFile(output), backup);
 await assert.rejects(buildPlace({ ...f, output, allowMissingAssets: true }), /Refusing to overwrite/);
 assert.deepEqual(await fs.readFile(output), backup);
 const checked = await validateAssets({ ...f, allowMissingAssets: true }); assert.equal(checked.missing.length, 1);
});
test('corrupt native files and accidental Folder exports are not silently skipped', async t => {
 const f = await fixture(t), source = path.join(f.directory, 'models/tree-large.rbxmx');
 await fs.writeFile(source, 'not a model'); await assert.rejects(validateAssets(f), /rojo sourcemap failed/);
 await fs.writeFile(source, MODEL_XML.replace('class="Model" referent="RBX0"', 'class="Folder" referent="RBX0"'));
 await assert.rejects(validateAssets(f), /export exactly the imported Model/);
});
test('duplicate format exports are rejected and source bytes are not touched', async t => {
 const f = await fixture(t), model = path.join(f.directory, 'models/tree-large.rbxmx');
 await fs.writeFile(model, MODEL_XML); await fs.writeFile(path.join(f.directory, 'models/tree-large.rbxm'), 'binary duplicate');
 await assert.rejects(validateAssets(f), /Duplicate model export/); assert.equal(await fs.readFile(model, 'utf8'), MODEL_XML);
});
test('the real project mounts version-controlled exports and protects unexported Studio children', async () => {
 const project = JSON.parse(await fs.readFile(path.join(ROOT, 'default.project.json'), 'utf8'));
 const mount = project.tree.ServerStorage.BattleWorksAssets;
 assert.equal(mount.$path, 'assets/roblox'); assert.equal(mount.$ignoreUnknownInstances, true);
 for (const extension of ['rbxm', 'rbxmx']) {
  const result = run('git', ['-C', ROOT, 'check-ignore', '--quiet', '--no-index', `assets/roblox/tree-large.${extension}`]);
  assert.equal(result.status, 1, 'model exports must not be ignored by Git');
 }
 assert.equal(run('git', ['-C', ROOT, 'check-ignore', '--quiet', '--no-index', 'unrelated-generated.rbxm']).status, 0);
});
test('asset-preserving build CLI has explicit validation and no-write argument checks', () => {
 const cli = path.join(ROOT, 'tools/build-place.js');
 assert.equal(run(process.execPath, [cli, '--help']).status, 0);
 const invalid = run(process.execPath, [cli, '--check', '--output', 'existing-place.rbxl']);
 assert.notEqual(invalid.status, 0); assert.match(invalid.stderr, /does not write a place/);
});
test('a Model without PrimaryPart retains its authored world pivot', async t => {
 const f = await fixture(t), source = path.join(f.directory, 'models/tree-large.rbxmx');
 const pivot = '<OptionalCoordinateFrame name="WorldPivotData"><CFrame><X>5</X><Y>6</Y><Z>7</Z><R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12><R20>0</R20><R21>0</R21><R22>1</R22></CFrame></OptionalCoordinateFrame>';
 await fs.writeFile(source, MODEL_XML.replace('<Ref name="PrimaryPart">RBX1</Ref>', pivot));
 const output = path.join(f.directory, 'pivot.rbxlx'); await buildPlace({ ...f, output });
 assert.match(await fs.readFile(output, 'utf8'), /<OptionalCoordinateFrame name="WorldPivotData">\s*<CFrame>\s*<X>5<\/X>\s*<Y>6<\/Y>\s*<Z>7<\/Z>/);
});
