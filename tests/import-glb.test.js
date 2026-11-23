'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {importGlb, cloudModel, cloudReference} = require('../tools/import-glb');

const model = '<roblox version="4"><Item class="Model" referent="M"><Properties><string name="Name">Bridge</string></Properties><Item class="MeshPart" referent="P"><Properties><string name="Name">Deck</string></Properties></Item></Item></roblox>';
const glb = path.resolve(__dirname, '../GLBs/forest/bridge.glb');
const silent = () => {};

test('native import packages original GLB, paired collision, native model and catalog without replacing assets', async t => {
 const root = await fs.mkdtemp(path.join(os.tmpdir(), 'bw-glb-import-'));
 t.after(() => fs.rm(root, {recursive: true, force: true}));
 await fs.mkdir(path.join(root, 'assets/roblox'), {recursive: true});
 await fs.mkdir(path.join(root, 'worlds'));
 const registry = path.join(root, 'worlds/roblox-assets.json');
 const native = path.join(root, 'bridge.rbxmx');
 await fs.writeFile(registry, '{}');
 await fs.writeFile(native, model);
 await fs.writeFile(path.join(root, 'worlds/asset-collision-generation.json'), '{"enabled":true,"sourceFolders":{"Forest":"GLBs/forest"}}');
 const item = await importGlb(root, 'Forest/custom_bridge', glb, {native, collision: glb}, silent);
 assert.equal(item.packaged, true);
 assert.equal(item.collider.explicitCollision, true);
 assert.deepEqual(item.resizeAxes,[true,true,true],'explicit collision enables all stretch axes unless overridden');
 const report = JSON.parse(await fs.readFile(path.join(root, 'assets/collision-report.json')));
 assert.equal(report.assets[0].collisionSource, 'GLBs/forest/custom_bridge.collision.glb');
 assert.equal(report.assets[0].faces, item.collider.faces.length);
 assert.equal(await fs.readFile(path.join(root, 'assets/roblox/Forest/custom_bridge.rbxmx'), 'utf8'), model);
 const originalRegistry = await fs.readFile(registry, 'utf8');
 await assert.rejects(importGlb(root, 'Forest/custom_bridge', glb, {native}, silent), /already exists/);
 const combined = await importGlb(root, 'Forest/single_bridge', glb, {native}, silent);
 assert.ok(combined.packaged && !combined.collider.explicitCollision);
 const invalid = path.join(root, 'invalid.rbxmx');
 await fs.writeFile(invalid, '<roblox>broken native model</roblox>');
 const beforeInvalid = await fs.readFile(registry, 'utf8');
 await assert.rejects(importGlb(root, 'Forest/broken', glb, {native: invalid}, silent));
 assert.equal(await fs.readFile(registry, 'utf8'), beforeInvalid);
 assert.ok(beforeInvalid.includes('single_bridge') && !originalRegistry.includes('single_bridge'));
 await assert.rejects(fs.access(path.join(root, 'GLBs/forest/broken.glb')), {code:'ENOENT'});
 const reference={assetId:'456',creatorId:'123',creatorType:'User'};
 const remote = await importGlb(root,'Forest/cloud_bridge',glb,{'asset-id':'456'},silent,async()=>reference);
 assert.deepEqual(remote.cloudModel,reference);
 assert.equal(remote.packaged,false);
 const updatedReport=JSON.parse(await fs.readFile(path.join(root,'assets/collision-report.json')));
 assert.equal(updatedReport.assets.find(item=>item.asset==='Forest/cloud_bridge').delivery,'roblox');
 assert.equal(updatedReport.summary.unavailable,0);
 assert.deepEqual(await fs.readdir(path.join(root,'assets/roblox/Forest')),['custom_bridge.rbxmx','single_bridge.rbxmx']);
});

test('Open Cloud uploads visual bytes, polls, then downloads without forwarding credentials to CDN', async () => {
 const calls = [];
 const fetcher = async (url, options) => {
  calls.push({url: String(url), options});
  if (calls.length === 1) {
   assert.equal(options.body.get('fileContent').type, 'model/gltf-binary');
   assert.equal(JSON.parse(options.body.get('request')).creationContext.creator.groupId, '123');
   return Response.json({path: 'operations/operation-1'});
  }
  if (calls.length === 2) return Response.json({done: false});
  if (calls.length === 3) return Response.json({done: true, response: {assetId: '456'}});
  if (calls.length === 4) return Response.json({location: 'https://c0.rbxcdn.com/model'});
  assert.equal(options.headers, undefined);
  return new Response(model, {headers: {'content-type':'application/octet-stream'}});
 };
 const result = await cloudModel(Buffer.from('visual'), {name:'Bridge'}, silent, {ROBLOX_API_KEY:'test', ROBLOX_GROUP_ID:'123'}, fetcher, async()=>{});
 assert.equal(result.toString(), model);
 assert.match(calls[3].url, /assetId\/456$/);
 assert.equal(calls[3].options.headers['x-api-key'], 'test');
 await assert.rejects(cloudModel(Buffer.alloc(0), {'asset-id':'456'}, silent, {ROBLOX_API_KEY:'test'},
  async()=>Response.json({location:'https://example.com/model'})), /unexpected download host/);
});
test('download permission failure explains how to reuse the asset and redacts the API key', async () => {
 const key = 'example-private-key';
 const fetcher = async (_, options) => {
  assert.equal(options.method, undefined);
  return Response.json({errors:[{message:`Scope not authorized. ${key}`}]}, {status:403});
 };
 await assert.rejects(cloudModel(Buffer.alloc(0), {'asset-id':'456'}, silent, {ROBLOX_API_KEY:key}, fetcher), error => {
  assert.match(error.message, /Scope not authorized/);
  assert.match(error.message, /legacy-asset:manage/);
  assert.match(error.message, /--asset-id 456/);
  assert.ok(!error.message.includes(key));
  return true;
 });
});
test('cloud reference verifies an existing owned Model without upload or Asset Delivery', async () => {
 const env={ROBLOX_API_KEY:'test',ROBLOX_USER_ID:'123'};
 const reference=await cloudReference(Buffer.alloc(0),{'asset-id':'456'},silent,env,async(url,options)=>{
  assert.equal(String(url),'https://apis.roblox.com/assets/v1/assets/456');
  assert.equal(options.method,undefined);
  assert.equal(options.headers['x-api-key'],'test');
  return Response.json({assetId:'456',assetType:'Model',creationContext:{creator:{userId:'123'}}});
 });
 assert.deepEqual(reference,{assetId:'456',creatorId:'123',creatorType:'User'});
 await assert.rejects(cloudReference(Buffer.alloc(0),{'asset-id':'456'},silent,env,async()=>
  Response.json({assetId:'456',assetType:'Model',creationContext:{creator:{userId:'999'}}})),/configured creator/);
});
