'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
const {loadFaces,extractPairedFaces}=require('./glb-collision');
async function generateCollisions(root,items){
 let config;try{config=JSON.parse(await fs.readFile(path.join(root,'worlds/asset-collision-generation.json'),'utf8'));}catch(e){if(e.code==='ENOENT')return null;throw e;}
 if(!config.enabled)return null;
 const report=[];const cache=new Map();
 for(const item of items){
  if(item.model.startsWith('Builtin/'))continue;
  const logical=item.palettePath||item.model,segments=logical.split('/');
  let source;
  if(item.collisionSource)source=item.source;
  else if(config.sourceFolders?.[segments[0]])source=path.join(config.sourceFolders[segments[0]],...segments.slice(1))+'.glb';
  else if(/\.glb$/i.test(item.source))source=item.source;
  let profile,reason;
  try{
   if(!source)throw new Error('No source GLB mapping; sampling native model');
   const filename=path.resolve(root,source);
   if(!filename.startsWith(path.resolve(root)+path.sep))throw new Error('Source GLB escapes project root');
   const collision=item.collisionSource&&path.resolve(root,item.collisionSource);
   if(collision&&!collision.startsWith(path.resolve(root)+path.sep))throw new Error('Collision GLB escapes project root');
   const key=JSON.stringify([filename,collision]);
   if(!cache.has(key))cache.set(key,collision?extractPairedFaces(await fs.readFile(filename),await fs.readFile(collision)):await loadFaces(filename,{preserveClearance:true}));
   profile=cache.get(key);
   if(JSON.stringify(profile).length>170000)throw new Error('Profile exceeds per-asset metadata budget; sampling native model');
  }catch(e){
   if(item.collisionSource||e.explicitCollision||profile?.explicitCollision)throw new Error(`${item.model} (${source}): ${e.message}`,{cause:e});
   reason=e.message;
  }
  // Geometry is processed regardless of asset category. Preserve author flags,
  // durability, IDs and scale; actual surfaces replace old trunk/outer fractions.
  item.collider={widthFraction:1,heightFraction:1,depthFraction:1,...(profile?{fit:'faces',...profile}:{fit:'mesh'})};
  report.push({asset:item.model,packaged:!!item.packaged,...(item.cloudModel?{delivery:'roblox',assetId:item.cloudModel.assetId}:{}),source:source?.split(path.sep).join('/'),...(item.collisionSource?{collisionSource:item.collisionSource}:{}),fit:item.collider.fit,faces:profile?.faces.length||0,walls:profile?.walls.length||0,...(profile?.explicitCollision?{explicitCollision:true}:{}),...(reason?{reason}:{})});
 }
 return {version:1,assets:report,summary:{processed:report.length,faces:report.filter(i=>i.fit==='faces').length,sampled:report.filter(i=>i.fit==='mesh').length,unavailable:report.filter(i=>!i.packaged&&!i.delivery).length}};
}
module.exports={generateCollisions};
