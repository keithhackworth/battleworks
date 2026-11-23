#!/usr/bin/env node
'use strict';

const fs=require('node:fs/promises');
const path=require('node:path');
const {parseArgs}=require('node:util');
const {createInterface}=require('node:readline/promises');
const {compileFile}=require('./world/compiler');
const {validatePath}=require('./world/asset-path');
const {findExport}=require('./native-assets');
const {catalogData}=require('./world-builder/catalog');
const {readHiddenAssets,hiddenAssetFile}=require('./world-builder/hidden-assets');

async function optional(file){
 try{return await fs.readFile(file);}
 catch(error){if(error.code!=='ENOENT')throw error;return null;}
}
async function worldReferences(root,identities){
 const worlds=new Map();
 const record=id=>{
  if(!worlds.has(id))worlds.set(id,{files:[],used:false});
  return worlds.get(id);
 };
 async function visit(directory){
  let entries;
  try{entries=await fs.readdir(directory,{withFileTypes:true});}
  catch(error){if(error.code==='ENOENT')return;throw error;}
  for(const entry of entries.sort((a,b)=>a.name.localeCompare(b.name))){
   const file=path.join(directory,entry.name);
   if(entry.isDirectory()){await visit(file);continue;}
   if(!entry.isFile()||!entry.name.endsWith('.json')||entry.name.endsWith('.model.json'))continue;
   const doc=JSON.parse(await fs.readFile(file,'utf8'));
   const world=doc.version===1&&Array.isArray(doc.instances)?await compileFile(file):doc;
   if(![world.schemaVersion,world.version].some(version=>version===1||version===2)||
      typeof world.id!=='string'||!Array.isArray(world.objects))continue;
   const info=record(world.id);
   info.files.push(file);
   info.used ||= world.objects.some(object=>[object.asset,object.type,object.source].some(value=>identities.has(value)));
  }
 }
 await visit(path.join(root,'worlds'));
 await visit(path.join(root,'build/worlds'));
 const catalogFile=path.join(root,'worlds/studio-worlds.model.json');
 const catalog=JSON.parse((await optional(catalogFile))||'null');
 const worldId=entry=>entry.Children?.find(child=>child.Name==='WorldId')?.Properties?.Value;
 const usesAsset=node=>(
  ['Template','AssetId','Source'].includes(node.Name)&&identities.has(node.Properties?.Value)
 )||node.Children?.some(usesAsset);
 for(const entry of catalog?.Children||[]){
  const id=worldId(entry);
  if(typeof id==='string'&&usesAsset(entry))record(id).used=true;
 }
 return new Map([...worlds].filter(([,info])=>info.used).sort(([a],[b])=>a.localeCompare(b)));
}

async function confirmHide(count){
 if(!process.stdin.isTTY)throw new Error('Referenced worlds require interactive confirmation. Rerun --apply in a terminal.');
 const prompt=createInterface({input:process.stdin,output:process.stdout});
 const cancelled=new AbortController();
 prompt.once('close',()=>cancelled.abort());
 prompt.once('SIGINT',()=>prompt.close());
 try{
  const answer=await prompt.question(`Hide the asset from the picker? ${count} existing world(s) will keep their placements. [y/N] `,{signal:cancelled.signal});
  return /^(y|yes)$/i.test(answer.trim());
 }catch(error){
  if(error.name==='AbortError')return false;
  throw error;
 }finally{prompt.close();}
}

async function deleteAsset(root,requested,options={},log=console.log){
 const asset=validatePath(requested.replace(/^\//,''));
 const lockPath=path.join(root,'assets/roblox/.import-glb.lock');
 const lock=await fs.open(lockPath,'wx');
 try{
  const {items,exports,collisionReport}=await catalogData(root);
  const names=item=>[item.model,item.palettePath,item.model.startsWith('Builtin/')?'Builtin/'+item.name:undefined];
  const exact=items.filter(item=>names(item).includes(asset));
  const matches=exact.length?exact:items.filter(item=>names(item).some(name=>name?.toLowerCase()===asset.toLowerCase()));
  if(matches.length>1)throw new Error(`Ambiguous asset path. Use an exact catalog path: ${matches.map(item=>item.model).join(', ')}`);
  const item=matches[0]||items.find(item=>item.model==='Builtin/BW_water'&&asset.toLowerCase()==='builtin/shallow water');
  if(!item)throw new Error(`No asset found at ${asset}`);
  const native=findExport(exports,item.model);
  const aliases=items.filter(candidate=>candidate===item||(native&&findExport(exports,candidate.model)===native));
  const identities=new Set(aliases.flatMap(candidate=>[candidate.model,candidate.palettePath,candidate.id,candidate.id.replace(/^asset\./,'')].filter(Boolean)));
  if(native)identities.add(native.nativePath);
  const inferredSources=new Map(collisionReport?.assets.map(entry=>[entry.asset,entry.source]));
  const sources=candidate=>[candidate.source,inferredSources.get(candidate.model)];
  const sharedSources=new Set(items.filter(candidate=>!aliases.includes(candidate)).flatMap(sources));
  for(const source of aliases.flatMap(sources)){
   if(source&&!sharedSources.has(source))identities.add(source);
  }
  const worlds=await worldReferences(root,identities);
  const hidden=await readHiddenAssets(root);
  log(`Asset: ${item.model}`);
  log(`Repository worlds using this asset: ${worlds.size} (hosted worlds excluded)`);
  for(const [id,{files}] of worlds){
   log(`  ${id} (${files.length?files.map(file=>path.relative(root,file)).join(', '):'Studio world catalog'})`);
  }
  if(aliases.every(candidate=>hidden.includes(candidate.model))){log('Already hidden from the object picker.');return;}
  if(!options.apply){log('Preview only. Add --apply to hide this asset from the object picker.');return;}
  if(worlds.size&&!await (options.confirm||confirmHide)(worlds.size)){
   log('Cancelled. Asset visibility is unchanged.');
   return;
  }
  const updated=[...new Set([...hidden,...aliases.map(candidate=>candidate.model)])].sort();
  const file=hiddenAssetFile(root),pending=file+'.pending';
  await fs.writeFile(pending,JSON.stringify({ClassName:'StringValue',Properties:{Value:JSON.stringify(updated)}},null,2)+'\n');
  await fs.rename(pending,file);
  log(`Hidden ${item.model}. Existing placements are preserved. Sync Rojo and restart Play to refresh the object picker.`);
 }finally{
  await lock.close();
  await fs.unlink(lockPath);
 }
}

if(require.main===module) (async()=>{
 const {positionals,values}=parseArgs({allowPositionals:true,options:{apply:{type:'boolean'}}});
 if(positionals.length!==1)throw new Error('Usage: node tools/delete-asset.js /Forest/Bridge [--apply]');
 await deleteAsset(path.resolve(__dirname,'..'),positionals[0],values);
})().catch(error=>{console.error(error.message);process.exitCode=1;});
module.exports={deleteAsset};
