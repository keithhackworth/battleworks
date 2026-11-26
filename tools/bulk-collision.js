'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
const {extractFaces,extractPairedFaces,readGlb,isCollisionNode}=require('./glb-collision');
// Signed, one-based source axes in native X/Y/Z order. Keep Y vertical
// because face undersides are stored as scalar heights.
function alignProfile(profile,axes){
 if(!profile||axes===undefined)return profile;
 if(!Array.isArray(axes)||axes.length!==3||axes[1]!==2||
    !axes.every(Number.isInteger)||new Set(axes.map(Math.abs)).size!==3||
    !axes.every(axis=>Math.abs(axis)>=1&&Math.abs(axis)<=3))throw new Error('Invalid native collision axes');
 const point=vertex=>axes.map(axis=>Math.sign(axis)*vertex[Math.abs(axis)-1]||0);
 const reflected=(Math.abs(axes[0])===3?-1:1)*Math.sign(axes[0]*axes[2])<0;
 const triangles=faces=>faces.map(face=>(reflected?[face[0],face[2],face[1]]:face).map(point));
 return {...profile,sourceSize:axes.map(axis=>profile.sourceSize[Math.abs(axis)-1]),
  faces:triangles(profile.faces),...(profile.walls&&{walls:triangles(profile.walls)}),
  ...(profile.snap&&{snap:{faces:triangles(profile.snap.faces),segments:profile.snap.segments.map(edge=>edge.map(point))}})};
}
async function generateCollisions(root,items){
 let config;try{config=JSON.parse(await fs.readFile(path.join(root,'worlds/asset-collision-generation.json'),'utf8'));}catch(e){if(e.code==='ENOENT')return null;throw e;}
 if(!config.enabled)return null;
 const report=[];const cache=new Map();
 for(const item of items){
  if(item.model.startsWith('Builtin/'))continue;
  const logical=item.palettePath||item.model,segments=logical.split('/');
  let source;
  if(item.collisionSource||/\.with-collision\.glb$/i.test(item.source))source=item.source;
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
   if(!cache.has(key)){
    const bytes=await fs.readFile(filename);
    const extracted=collision?extractPairedFaces(bytes,await fs.readFile(collision)):extractFaces(bytes,{preserveClearance:true});
    const collisionNodes=collision?[]:(readGlb(bytes).json.nodes||[]).filter(node=>node?.mesh!==undefined&&isCollisionNode(node?.name));
    cache.set(key,{extracted,automatic:collisionNodes.length>0&&collisionNodes.every(node=>node.extras?.battleWorksAutoCollision)});
   }
   const {extracted,automatic}=cache.get(key);
   const axes=config.nativeProfileAxes?.[item.model];
   profile=alignProfile(extracted,axes);
   if(JSON.stringify(profile).length>170000)throw new Error('Profile exceeds per-asset metadata budget; sampling native model');
   if(automatic&&!axes)item.checkNativeProfile=true;
  }catch(e){
   if(item.collisionSource||e.explicitCollision||e.explicitSnap||profile?.explicitCollision||profile?.snap)throw new Error(`${item.model} (${source}): ${e.message}`,{cause:e});
   reason=e.message;
  }
  // Geometry is processed regardless of asset category. Preserve author flags,
  // durability, IDs and scale; actual surfaces replace old trunk/outer fractions.
  item.collider={widthFraction:1,heightFraction:1,depthFraction:1,...(profile?{fit:'faces',...profile}:{fit:'mesh'})};
  report.push({asset:item.model,packaged:!!item.packaged,...(item.cloudModel?{delivery:'roblox',assetId:item.cloudModel.assetId}:{}),source:source?.split(path.sep).join('/'),...(item.collisionSource?{collisionSource:item.collisionSource}:{}),fit:item.collider.fit,faces:profile?.faces.length||0,walls:profile?.walls.length||0,...(profile?.explicitCollision?{explicitCollision:true}:{}),...(reason?{reason}:{})});
 }
 return {version:1,assets:report,summary:{processed:report.length,faces:report.filter(i=>i.fit==='faces').length,sampled:report.filter(i=>i.fit==='mesh').length,unavailable:report.filter(i=>!i.packaged&&!i.delivery).length}};
}
module.exports={generateCollisions,alignProfile};
