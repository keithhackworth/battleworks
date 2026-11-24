#!/usr/bin/env node
'use strict';
const fs = require('node:fs/promises');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {parseArgs} = require('node:util');
const {setTimeout: sleep} = require('node:timers/promises');
const {cloudAssetId, request} = require('./import-glb');
const {catalogModel,decodeCatalogModel} = require('./catalog-chunks');

const formats = {'.mp3':'audio/mpeg','.ogg':'audio/ogg','.wav':'audio/wav','.flac':'audio/flac'};
const hash = value => createHash('sha256').update(value).digest('hex');
const display = text => text.replace(/[_-]+/g, ' ').replace(/\b\w/g, letter => letter.toUpperCase());

async function filesAt(name) {
 const stat = await fs.lstat(name);
 if (stat.isSymbolicLink()) return [];
 if (!stat.isDirectory()) return formats[path.extname(name).toLowerCase()] ? [name] : [];
 const files = [];
 for (const child of (await fs.readdir(name)).sort()) files.push(...await filesAt(path.join(name, child)));
 return files;
}
async function importSfx(root, target, options = {}, log = console.log, env = process.env, fetcher = fetch, wait = sleep) {
 const sourceRoot = path.join(root,'SFX');
 const targetPath = path.resolve(root,target);
 const targetReal = await fs.realpath(targetPath);
 const sourceReal = await fs.realpath(sourceRoot);
 if (targetReal !== sourceReal && !targetReal.startsWith(sourceReal + path.sep)) throw new Error('Place source files under SFX/ first.');
 const files = await filesAt(targetReal);
 if (!files.length) throw new Error('No supported audio found (.mp3, .ogg, .wav, .flac).');
 if ((options.operation || options['asset-id']) && files.length !== 1) throw new Error('Resume options require one audio file.');
 const catalog = path.join(root,'assets/sfx-catalog.model.json');
 const lock = catalog + '.lock';
 await fs.mkdir(path.dirname(catalog),{recursive:true});
 try { await fs.mkdir(lock); }
 catch (error) { if(error.code === 'EEXIST') throw new Error('Another SFX importer holds the catalog lock.'); throw error; }
 const failures = [];
 const results = [];
 try {
  let items = [];
  try { items = decodeCatalogModel(JSON.parse(await fs.readFile(catalog,'utf8'))); }
  catch(error) { if(error.code !== 'ENOENT') throw error; }
  for (const file of files) {
   const source = path.relative(sourceReal,file).split(path.sep).join('/');
   try {
    const {size} = await fs.stat(file);
    if (size <= 0 || size >= 20_000_000) throw new Error('Audio must be nonempty and under 20 MB.');
    const bytes = await fs.readFile(file);
    const digest = hash(bytes);
    const key = 'sfx_' + hash(source).slice(0,24);
    const existing = items.find(item => item.key === key);
    const same = items.find(item => item.sha256 === digest);
    const extension = path.extname(file);
    const name = display(path.basename(file,extension)).slice(0,50);
    const category = source.includes('/') ? display(source.split('/')[0]) : 'Miscellaneous';
    if (existing?.sha256 === digest && !options.operation && !options['asset-id'] && !options['refresh-status']) {
     log(`Unchanged: ${source} (${existing.assetId})`); results.push(existing); continue;
    }
    const assetId = (!options.operation && !options['asset-id'] && same?.assetId) || await cloudAssetId(bytes,{
     ...options, assetType:'Audio', name, description:'BattleWorks sound effect',
     mime:formats[extension.toLowerCase()], fileName:`sound${extension.toLowerCase()}`,
    },log,env,fetcher,wait);
    let moderation = same?.assetId === assetId ? same.moderation : undefined;
    if ((!moderation || moderation==='Unknown' || options['refresh-status']) && env.ROBLOX_API_KEY) {
     try {
      const response = await request(fetcher,`https://apis.roblox.com/assets/v1/assets/${assetId}`,{headers:{'x-api-key':env.ROBLOX_API_KEY}});
      moderation = (await response.json()).moderationResult?.moderationState || moderation;
     } catch (error) { log(`Metadata unavailable: ${error.message}. Check Assets Read permission and the creator if needed.`); }
    }
    const item = {key,name,category,source,assetId,sha256:digest,moderation:moderation || 'Unknown'};
    const next = items.filter(record => record.key !== key).concat(item).sort((a,b) => a.source.localeCompare(b.source));
    const temporary = path.join(lock,'catalog.json');
    await fs.writeFile(temporary,JSON.stringify(catalogModel(next),null,2)+'\n');
    await fs.rename(temporary,catalog);
    items = next; results.push(item);
    log(`Registered: ${source} → ${assetId} (moderation: ${item.moderation}). Verify experience audio access in Creator Hub.`);
   } catch(error) { failures.push(`${source}: ${error.message}`); }
  }
 } finally { await fs.rm(lock,{recursive:true,force:true}); }
 if (failures.length) throw new Error(failures.join('\n'));
 return results;
}
if(require.main === module) (async()=>{
 const {values,positionals} = parseArgs({allowPositionals:true,options:{operation:{type:'string'},'asset-id':{type:'string'},'refresh-status':{type:'boolean'}}});
 if(positionals.length !== 1) throw new Error('Usage: node tools/import-sfx.js SFX/<file-or-directory> [--operation ID | --asset-id ID] [--refresh-status]');
 await importSfx(path.resolve(__dirname,'..'),positionals[0],values);
})().catch(error=>{console.error(error.message);process.exitCode=1;});
module.exports={importSfx};
