'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {importUI} = require('../tools/import-ui');

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=', 'base64');
const replacement = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAQAAABeK7cBAAAADUlEQVR4nGNkYGBgAAAACgAC4y4RgwAAAABJRU5ErkJggg==', 'base64');

test('UI imports preserve paths, source bytes, and references across updates and failures', async t => {
 const root = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-ui-'));
 t.after(() => fs.rm(root, {recursive: true, force: true}));
 const write = async (file, bytes) => {
  await fs.mkdir(path.dirname(path.join(root, file)), {recursive: true});
  await fs.writeFile(path.join(root, file), bytes);
 };
 const read = file => fs.readFile(path.join(root, file));
 const manifest = 'assets/ui-manifest.json';
 const registry = 'src/shared/UIAssetData.luau';
 const worldCatalog = 'assets/editor-catalog.model.json';
 const env = {ROBLOX_API_KEY: 'test-key', ROBLOX_GROUP_ID: '123'};
 let attempts = 0;
 let fail = false;
 let expected = png;
 const fetcher = async (url, options) => {
  assert.equal(options.headers['x-api-key'], env.ROBLOX_API_KEY);
  if (options.method === 'POST') {
   attempts++;
   assert.equal(url, 'https://apis.roblox.com/assets/v1/assets');
   const request = JSON.parse(options.body.get('request'));
   assert.equal(request.assetType, 'Image');
   assert.deepEqual(request.creationContext.creator, {groupId: '123'});
   const image = options.body.get('fileContent');
   assert.equal(image.type, 'image/png');
   assert.deepEqual(Buffer.from(await image.arrayBuffer()), expected);
   return Response.json({path: 'operations/upload_' + attempts});
  }
  assert.match(url, /\/operations\/upload_\d+$/);
  return Response.json(fail ? {done: true, error: {message: 'image rejected'}} :
   {done: true, response: {assetId: String(40 + attempts)}});
 };
 const logs = [];
 const run = (source, flags) => importUI(root, source, flags, msg => logs.push(msg), env, fetcher);
 await write('staging/corners/top-left/01.png', png);
 await write('staging/edges/top/01.PNG', png);
 await write('staging/README.txt', 'ignored');
 await write(worldCatalog, 'unchanged world catalog');
 await write(registry, '');

 await run('staging', {into: 'footlockers/olive', 'dry-run': true});
 assert.equal(attempts, 0);
 assert.ok(logs.includes('Would upload: footlockers/olive/corners/top-left/01.png'));
 await assert.rejects(read(manifest), {code: 'ENOENT'});
 await assert.rejects(run('staging', {into: '../worlds'}), /relative directory/);

 await run('staging', {into: 'footlockers/olive'});
 const corner = 'footlockers/olive/corners/top-left/01.png';
 const edge = 'footlockers/olive/edges/top/01.PNG';
 const cornerFile = 'assets/ui/' + corner;
 const entries = async () => JSON.parse(await read(manifest)).images;
 assert.deepEqual((await entries()).map(image => image.source), [corner, edge]);
 assert.deepEqual((await entries())[0], {
  name: '01', source: corner, assetId: '41', width: 1, height: 1,
  sha256: createHash('sha256').update(png).digest('hex'),
 });
 assert.deepEqual(await read(cornerFile), png);
 assert.ok((await read(registry)).includes(corner));
 await run('assets/ui/footlockers/olive');
 assert.equal(attempts, 2);

 await write('updated/01.png', replacement);
 expected = replacement;
 fail = true;
 const before = await read(registry);
 await assert.rejects(run('updated/01.png', {into: 'footlockers/olive/corners/top-left'}), /01.png: Roblox rejected/);
 assert.equal((await entries())[0].assetId, '41');
 assert.deepEqual(await read(registry), before);
 assert.deepEqual(await read(cornerFile), png);

 fail = false;
 await run('updated/01.png', {into: 'footlockers/olive/corners/top-left'});
 assert.equal((await entries())[0].assetId, '44');
 assert.equal((await entries())[0].width, 2);
 assert.deepEqual(await read(cornerFile), replacement);
 await run(cornerFile, {force: true});
 assert.equal((await entries())[0].assetId, '45');
 assert.equal(String(await read(worldCatalog)), 'unchanged world catalog');

 await write('staging/bad.png', png.subarray(0, -2));
 await assert.rejects(run('staging/bad.png', {'dry-run': true}), /truncated PNG/);
 assert.equal(attempts, 5);
});

test('trim uploads cropped pixels, preserves originals, and caches by trim mode', async t => {
 const {spawnSync} = require('node:child_process');
 if (!['magick', 'convert'].some(command => spawnSync(command, ['-version']).status === 0)) {
  t.skip('ImageMagick is unavailable');
  return;
 }
 const root = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-ui-trim-'));
 t.after(() => fs.rm(root, {recursive: true, force: true}));
 await fs.mkdir(path.join(root, 'assets/ui'), {recursive: true});
 await fs.mkdir(path.join(root, 'src/shared'), {recursive: true});
 const artwork = {
  'opaque.png': 'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAGCAIAAABxZ0isAAAAJUlEQVQI12P8//8/AzbAAqUZGRFi//8zMDAwMeAApEvA7MBwAgCxnwcLK2dhxAAAAABJRU5ErkJggg==',
  'transparent.png': 'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAGCAYAAAD+Bd/7AAAAI0lEQVQI12NgIAAYYYz/////R5FgZGRkYGBgYCJkAuUKCAIAbZsECCm/k1IAAAAASUVORK5CYII=',
 };
 for (const [name, base64] of Object.entries(artwork)) {
  await fs.writeFile(path.join(root, 'assets/ui', name), Buffer.from(base64, 'base64'));
 }
 const env = {ROBLOX_API_KEY: 'test-key', ROBLOX_USER_ID: '123'};
 const uploads = [];
 const fetcher = async (_url, options) => {
  if (options.method === 'POST') {
   const bytes = Buffer.from(await options.body.get('fileContent').arrayBuffer());
   uploads.push([bytes.readUInt32BE(16), bytes.readUInt32BE(20)]);
   return Response.json({path: 'operations/upload_' + uploads.length});
  }
  return Response.json({done: true, response: {assetId: String(40 + uploads.length)}});
 };
 const run = options => importUI(root, 'assets/ui', options, () => {}, env, fetcher);
 await run({trim: true, 'dry-run': true});
 assert.equal(uploads.length, 0);
 await run({trim: true});
 await run({trim: true});
 assert.deepEqual(uploads, [[4, 4], [4, 4]]);
 const manifest = JSON.parse(await fs.readFile(path.join(root, 'assets/ui-manifest.json')));
 for (const image of manifest.images) {
  assert.deepEqual([image.width, image.height, image.trimmed], [4, 4, true]);
  assert.deepEqual(await fs.readFile(path.join(root, 'assets/ui', image.source)), Buffer.from(artwork[image.source], 'base64'));
 }
 await run({});
 assert.deepEqual(uploads, [[4, 4], [4, 4], [8, 6], [8, 6]]);
});
