#!/usr/bin/env node
'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {isDeepStrictEqual} = require('node:util');
const {setTimeout: sleep} = require('node:timers/promises');
const {parseArgs} = require('node:util');
const {validatePath} = require('./world/asset-path');
const {extractFaces, extractPairedFaces, visualGlb} = require('./glb-collision');
const {nativeExports, findExport} = require('./native-assets');
const {buildEditorCatalog} = require('./build-editor-catalog');

const cloud = 'https://apis.roblox.com';
const maxBytes = 20 * 1024 * 1024;
const id = value => /^\d+$/.test(String(value)) && Number(value) > 0;

async function request(fetch, url, options = {}) {
 const res = await fetch(url, {signal: AbortSignal.timeout(60000), redirect: 'manual', ...options});
 if (res.status >= 300 && res.status < 400) return res;
 if (!res.ok) {
  let detail = '';
  if (new URL(url).origin === cloud && res.headers.get('content-type')?.includes('json')) {
   const body = await res.json().catch(() => null);
   const message = body?.errors?.[0]?.message ?? body?.message;
   if (typeof message === 'string') {
    const key = options.headers?.['x-api-key'];
    detail = ': ' + (key ? message.replaceAll(key, '[redacted]') : message).replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 300);
   }
  }
  throw Object.assign(new Error(`Roblox request failed (HTTP ${res.status}) at ${new URL(url).pathname}${detail}`), {status: res.status});
 }
 return res;
}

async function downloadModel(fetch, key, assetId) {
 let url = new URL(`/asset-delivery-api/v1/assetId/${assetId}`, cloud);
 for (let hop = 0; hop < 5; hop++) {
  if (url.protocol !== 'https:' || (url.origin !== cloud && !url.hostname.endsWith('.rbxcdn.com'))) {
   throw new Error('Roblox delivery returned an unexpected download host');
  }
  const res = await request(fetch, url, url.origin === cloud ? {headers: {'x-api-key': key}} : {});
  if (res.status >= 300 && res.status < 400) {
   const location = res.headers.get('location');
   if (!location) throw new Error('Roblox delivery redirect has no location');
   url = new URL(location, url);
  } else if (res.headers.get('content-type')?.includes('json')) {
   const result = await res.json();
   if (!result.location) throw new Error('Roblox delivery did not provide model content');
   url = new URL(result.location, url);
  } else {
   const bytes = Buffer.from(await res.arrayBuffer());
   if (bytes.length > maxBytes) throw new Error('Downloaded native model exceeds the import size limit');
   return bytes;
  }
 }
 throw new Error('Roblox delivery exceeded the redirect limit');
}

async function cloudAssetId(bytes, options, log, env, fetcher, wait) {
 const key = env.ROBLOX_API_KEY;
 if (!key) throw new Error('Set ROBLOX_API_KEY or use --native with a visual-only Studio export');
 let operation = options.operation;
 let assetId = options['asset-id'];
 if (assetId && !id(assetId)) throw new Error('Invalid Roblox asset ID');
 if (!assetId && !operation) {
  const group = env.ROBLOX_GROUP_ID, user = env.ROBLOX_USER_ID;
  if (Boolean(group) === Boolean(user) || !id(group || user)) throw new Error('Set exactly one of ROBLOX_GROUP_ID or ROBLOX_USER_ID');
  const creator = group ? {groupId: group} : {userId: user};
  const form = new FormData();
  form.append('request', JSON.stringify({assetType: 'Model', displayName: options.name, description: 'BattleWorks visual model', creationContext: {creator}}));
  form.append('fileContent', new Blob([bytes], {type: 'model/gltf-binary'}), 'model.glb');
  const response = await request(fetcher, `${cloud}/assets/v1/assets`, {method: 'POST', headers: {'x-api-key': key}, body: form});
  operation = (await response.json()).path;
 }
 if (!assetId) {
  operation = String(operation).replace(/^\/?operations\//, '');
  if (!/^[a-z0-9_-]+$/i.test(operation) || operation === 'undefined') throw new Error('Roblox did not return a valid operation ID');
  log(`Roblox operation: ${operation}. Resume with --operation ${operation}.`);
  for (let attempt = 0; attempt < 60; attempt++) {
   const res = await request(fetcher, `${cloud}/assets/v1/operations/${operation}`, {headers: {'x-api-key': key}});
   const status = await res.json();
   if (status.error) throw new Error(`Roblox rejected the upload: ${status.error.message || status.error.code || 'unknown error'}`);
   if (status.done) {
    assetId = status.response?.assetId;
    if (!id(assetId)) throw new Error('Roblox completed the operation without an asset ID');
    break;
   }
   await wait(3000);
  }
  if (!assetId) throw new Error(`Roblox upload is still processing. Resume with --operation ${operation}.`);
 }
 log(`Roblox asset: ${assetId}. Resume with --asset-id ${assetId} if needed.`);
 return String(assetId);
}

async function cloudReference(bytes, options, log, env = process.env, fetcher = fetch, wait = sleep) {
 const assetId = await cloudAssetId(bytes, options, log, env, fetcher, wait);
 const res = await request(fetcher, `${cloud}/assets/v1/assets/${assetId}`, {headers: {'x-api-key': env.ROBLOX_API_KEY}});
 const data = await res.json();
 const creator = data.creationContext?.creator;
 const group = env.ROBLOX_GROUP_ID;
 const kind = group ? 'groupId' : 'userId';
 const expected = group || env.ROBLOX_USER_ID;
 if (!id(expected) || Boolean(group) === Boolean(env.ROBLOX_USER_ID) || data.assetType !== 'Model' ||
   String(data.assetId) !== assetId || String(creator?.[kind]) !== expected) {
  throw new Error('Roblox metadata does not match a Model owned by the configured creator');
 }
 return {assetId, creatorId: expected, creatorType: group ? 'Group' : 'User'};
}

async function cloudModel(bytes, options, log, env = process.env, fetcher = fetch, wait = sleep) {
 const assetId = await cloudAssetId(bytes, options, log, env, fetcher, wait);
 try {
  return await downloadModel(fetcher, env.ROBLOX_API_KEY, assetId);
 } catch (error) {
  if (error.status !== 401 && error.status !== 403) throw error;
  throw new Error(`${error.message}\nRoblox asset ${assetId} already exists. Asset Delivery requires the legacy-asset:manage scope, which is separate from Assets Read. Resume with --asset-id ${assetId} without --download to register the Roblox model reference.`, {cause: error});
 }
}

async function readGLB(file) {
 const info = await fs.stat(file);
 if (!info.isFile() || info.size > maxBytes) throw new Error('GLB input must be a file no larger than 20 MiB');
 return fs.readFile(file);
}

async function importGlb(root, asset, sourceFile, options, log = console.log, resolveReference = cloudReference) {
 validatePath(asset);
 if (!/^(?:[a-z0-9_-]+\/)*[a-z0-9_-]+$/i.test(asset) || asset.startsWith('Builtin/')) {
  throw new Error('Use a native asset path such as Forest/rope_bridge');
 }
 const visualSource = await readGLB(sourceFile);
 const collisionSource = options.collision && await readGLB(options.collision);
 const visual = visualGlb(visualSource);
 if (collisionSource && visual !== visualSource) throw new Error('Choose either named collision meshes or a separate collision GLB');
 let profile;
 try {
  profile = collisionSource ? extractPairedFaces(visualSource, collisionSource) : extractFaces(visualSource, {preserveClearance: true});
  if (JSON.stringify(profile).length > 170000) throw new Error('Collision profile exceeds the catalog size limit');
 } catch (error) {
  if (collisionSource || visual !== visualSource || profile?.explicitCollision) throw error;
  profile = null;
  log(`Collision will use native sampling: ${error.message}`);
 }
 if (profile) log(`Collision: ${profile.faces.length} support faces, ${profile.walls?.length || 0} walls, explicit: ${Boolean(profile.explicitCollision)}.`);
 if (options['prepare-only']) {
  await fs.writeFile(options['prepare-only'], visual, {flag: 'wx'});
  return profile;
 }

 const registry = path.join(root, 'worlds/roblox-assets.json');
 const config = JSON.parse(await fs.readFile(path.join(root, 'worlds/asset-collision-generation.json'), 'utf8'));
 if (!config.enabled) throw new Error('Asset collision generation must be enabled');
 const nativeRoot = path.join(root, 'assets/roblox');
 const lockPath = path.join(nativeRoot, '.import-glb.lock');
 const lock = await fs.open(lockPath, 'wx');
 const created = [];
 let originalRegistry, changedRegistry = false;
 try {
  if (findExport(await nativeExports(nativeRoot), asset)) throw new Error(`Native model '${asset}' already exists. Choose a new asset path.`);
  const [category, ...name] = asset.split('/');
  const folder = config.sourceFolders?.[category];
  const stem = folder && name.length ? path.posix.join(folder, ...name) : path.posix.join('GLBs/imported', asset);
  const source = stem + '.glb';
  const collision = collisionSource && stem + '.collision.glb';
  async function addFile(relative, data, stage = false) {
   const target = path.resolve(root, relative);
   if (!target.startsWith(path.resolve(root) + path.sep)) throw new Error('Import path escapes the repository');
   await fs.mkdir(path.dirname(target), {recursive: true});
   try {await fs.writeFile(target, data, {flag: 'wx'});created.push(target);}
   catch (error) {
    if (error.code !== 'EEXIST' || stage || !(await fs.readFile(target)).equals(data)) throw error;
   }
  }
  await addFile(source, visualSource);
  if (collision) await addFile(collision, collisionSource);

  originalRegistry = await fs.readFile(registry, 'utf8');
  const bindings = JSON.parse(originalRegistry);
  const key = Object.keys(bindings).find(k => (bindings[k].path || bindings[k].model) === asset) ||
   createHash('sha256').update(asset).digest('hex').slice(0,16);
  if (bindings[key] && (bindings[key].path || bindings[key].model) !== asset) throw new Error('Asset binding ID conflict');
  const title = options.name || bindings[key]?.displayName || asset.split('/').at(-1).replaceAll('_', ' ');
  const cloudOptions = {...options, name: title};
  if (!options.native && !options.download && bindings[key]?.cloudModel && !options['asset-id'] && !options.operation) {
   throw new Error(`Asset already registered as Roblox model ${bindings[key].cloudModel.assetId}. Use --asset-id to verify or replace that reference.`);
  }
  let ext, reference;
  if (!options.native && !options.download) reference = await resolveReference(visual, cloudOptions, log);
  else {
   const model = options.native ? await fs.readFile(options.native) : await cloudModel(visual, cloudOptions, log);
   ext = model.subarray(0,8).toString() === '<roblox!' ? 'rbxm' :
    /^\s*(?:<\?xml[^>]*>\s*)?<roblox\b/.test(model.subarray(0,1024).toString()) ? 'rbxmx' : null;
   if (!ext) throw new Error('Roblox delivered no native RBXM/RBXMX model. Omit --download to register the Roblox asset ID.');
   await addFile(`assets/roblox/${asset}.${ext}`, model, true);
  }
  bindings[key] = {...bindings[key], model: asset, source, displayName: title};
  if (reference) bindings[key].cloudModel = reference;
  else delete bindings[key].cloudModel;
  if (collision) bindings[key].collisionSource = collision;
  else delete bindings[key].collisionSource;
  if (await fs.readFile(registry, 'utf8') !== originalRegistry) throw new Error('Asset registry changed during the import. Retry without uploading again.');
  await fs.writeFile(registry, JSON.stringify(bindings, null, 2) + '\n');
  changedRegistry = true;
  let item;
  await buildEditorCatalog(root, items => {
   item = items.find(item => item.model === asset);
   if ((!item?.packaged && (!reference || !isDeepStrictEqual(item?.cloudModel, reference))) || !item ||
     item.collider?.fit !== (profile ? 'faces' : 'mesh') ||
     (profile && !Object.keys(profile).every(key => isDeepStrictEqual(item.collider[key], profile[key])))) {
    throw new Error('Catalog could not match the native model to its verified collision profile');
   }
  });
  log(`Registered: ${asset} (${ext || 'Roblox model ' + reference.assetId}), ${profile ? profile.faces.length + ' collision faces' : 'native collision sampling'}. Sync Rojo and restart Play.`);
  return item;
 } catch (error) {
  if (changedRegistry) await fs.writeFile(registry, originalRegistry);
  for (const file of created.reverse()) await fs.unlink(file);
  throw error;
 } finally {
  await lock.close();
  await fs.unlink(lockPath);
 }
}

if (require.main === module) (async () => {
 const {positionals, values} = parseArgs({allowPositionals: true, options: {
  collision: {type: 'string'}, native: {type: 'string'}, name: {type: 'string'},
  'prepare-only': {type: 'string'}, 'asset-id': {type: 'string'}, operation: {type: 'string'},
  download: {type: 'boolean'},
 }});
 if (positionals.length !== 2) throw new Error('Usage: node tools/import-glb.js ASSET_PATH SOURCE.glb [--collision COLLISION.glb] [--native MODEL.rbxm | --prepare-only VISUAL.glb | --asset-id ID | --operation ID] [--download]');
 if (['native','prepare-only','asset-id','operation'].filter(key => values[key]).length > 1) throw new Error('Choose one import or resume option');
 if (values.download && (values.native || values['prepare-only'])) throw new Error('--download requires a Roblox cloud import');
 await importGlb(path.resolve(__dirname, '..'), ...positionals, values);
})().catch(error => {console.error(error.message);process.exitCode = 1;});

module.exports = {importGlb, cloudModel, cloudReference};
