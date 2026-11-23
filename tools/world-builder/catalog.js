'use strict';
const fs=require('node:fs/promises');
const path=require('node:path');
const {createHash}=require('node:crypto');
const {entriesFor,validResizeAxes,validCloudModel,validatePath}=require('../world/asset-path');
const {nativeExports,findExport}=require('../native-assets');
const builtins=[
 ['block','Block / obstacle','Rocks & obstacles',[8,5,8],'Block','Slate',[115,123,126],true,false],
 ['wall','Wall','Walls & fences',[12,6,1],'Block','Concrete',[155,155,145],true,false],
 ['house','Simple building','Buildings & structures',[14,12,12],'Block','Brick',[175,110,75],true,true],
 ['rock','Round rock','Rocks & obstacles',[7,4,6],'Ball','Slate',[110,120,125],true,false],
 ['tree','Simple tree','Trees & vegetation',[4,12,4],'Block','Wood',[110,80,45],true,true],
 ['road','Road section','Bridges & roads',[12,.08,24],'Block','Asphalt',[70,70,70],false,false],
 ['bridge','Bridge / ramp deck','Bridges & roads',[12,.2,24],'Block','WoodPlanks',[145,110,70],true,false],
 ['grass','Grass patch','Terrain & ground',[18,.06,18],'Block','Grass',[95,135,65],false,false],
 ['water','Shallow water (slowdown)','Water & hazards',[18,.1,18],'Ball','Glass',[67,156,183],false,false],
 ['mud','Mud (slowdown)','Water & hazards',[18,.08,18],'Ball','Mud',[103,70,43],false,false],
 ['crate','Crate','Special gameplay objects',[5,5,5],'Block','WoodPlanks',[155,115,65],true,true],
 ['decoration','Decoration','Decorations',[3,3,3],'Ball','SmoothPlastic',[220,185,80],false,false],
];
function builtinCatalog() {return builtins.map(([id,name,category,size,shape,material,color,solid,destructible])=>({id:`builtin.${id}`,name,category,source:`builtin/${id}.glb`,model:`Builtin/BW_${id}`,size,shape,material,color,stretchable:shape==='Block',defaultScale:1,solid,destructible,hp:100,collider:{widthFraction:1,depthFraction:1,heightFraction:1},...(id==='water'||id==='mud'?{zone:id==='water'?'Water':'Mud'}:{})}));}
async function catalogData(root) {
 const bindings=JSON.parse(await fs.readFile(path.join(root,'worlds/roblox-assets.json'),'utf8'));
 let profiles={};try{profiles=JSON.parse(await fs.readFile(path.join(root,'worlds/asset-collision-profiles.json'),'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
 const faceProfiles={};
 for(const [name,profile] of Object.entries(profiles))if(profile.fit==='faces'){
  if(name.startsWith('Builtin/')||typeof profile.source!=='string')throw new Error(`Invalid face profile '${name}'`);
  const filename=path.resolve(root,profile.source);
  if(!filename.startsWith(path.resolve(root)+path.sep))throw new Error(`Collision source escapes project: '${name}'`);
  faceProfiles[name]=await require('../glb-collision').loadFaces(filename);
 }
 const fitted=(name,collider)=>{
  const profile=profiles[name];if(!profile)return collider;
  if(!['mesh','faces'].includes(profile.fit)||name.startsWith('Builtin/'))throw new Error(`Unsupported collision profile '${name}'`);
  return {...collider,fit:profile.fit,...faceProfiles[name]};
 };
 const builtin=builtinCatalog();const reserved=new Set(builtin.map(i=>i.model));
 const exports=(await nativeExports(path.join(root,'assets/roblox'))).filter(e=>{
  if(e.nativePath.split('/')[0]==='__BattleWorksAssetIndex'||e.nativePath.split('/')[0]==='Builtin')throw new Error(`Native export '${e.nativePath}' collides with a reserved Rojo mount`);
  if(reserved.has(e.path))return false;
  if(e.path.startsWith('Builtin/'))throw new Error(`Asset '${e.path}' uses the reserved Builtin/ namespace`);
  return true;
 });
 const registered=entriesFor(bindings),known=new Set(registered.map(e=>e.model));
 const used=new Set();const paths=Object.fromEntries(exports.map(e=>[e.path,e.nativePath]));
 const imported=registered.map(e=>{
  const b=bindings[e.id],native=findExport(exports,e.model);
  if(b.cloudModel!==undefined&&(!validCloudModel(b.cloudModel)||native||e.model.startsWith('Builtin/')))throw new Error(`Invalid or conflicting Roblox model reference for '${e.model}'`);
  if(b.collisionSource!==undefined&&(typeof b.collisionSource!=='string'||!/\.glb$/i.test(b.collisionSource)||!/\.glb$/i.test(e.source)))throw new Error(`Invalid collisionSource for '${e.model}'`);
  if(native){used.add(native.nativePath);paths[e.model]=native.nativePath;}
  return {id:`asset.${e.id}`,name:b.displayName||e.model.split('/').at(-1),category:b.category||e.model.split('/').slice(0,-1).join(' / ')||(/tree/i.test(e.id)?'Trees & vegetation':/fence/i.test(e.id)?'Walls & fences':'Decorations'),source:e.source,model:e.model,...(b.cloudModel?{cloudModel:b.cloudModel}:{}),...(b.collisionSource?{collisionSource:b.collisionSource}:{}),...(native&&native.path!==e.model?{palettePath:native.path}:{}),defaultScale:45,size:b.size||null,solid:b.solid??!!e.collider,destructible:b.destructible??/tree/i.test(e.id),hp:150,collider:e.collider?fitted(native?.path||e.model,e.collider):null,packaged:!!native};
 });
 for(const entry of exports)if(!known.has(entry.path)&&!used.has(entry.nativePath))imported.push({id:'asset.'+createHash('sha256').update(entry.path).digest('hex').slice(0,16),name:entry.path.split('/').at(-1),category:entry.path.split('/').slice(0,-1).join(' / ')||'Decorations',source:entry.path,model:entry.path,defaultScale:45,size:null,solid:false,destructible:false,hp:100,collider:fitted(entry.path,{widthFraction:1,depthFraction:1,heightFraction:1}),packaged:true});
 const collisionReport=await require('../bulk-collision').generateCollisions(root,imported);
 let resizing={};
 try{resizing=JSON.parse(await fs.readFile(path.join(root,'worlds/asset-resizing.json'),'utf8'));}
 catch(error){if(error.code!=='ENOENT')throw error;}
 for(const [asset,axes] of Object.entries(resizing)){
  validatePath(asset);
  if(!validResizeAxes(axes)||!imported.some(item=>item.model===asset||item.palettePath===asset))throw new Error(`Invalid or unknown resizable imported asset '${asset}'`);
 }
 for(const item of imported){
  const axes=resizing[item.model]||resizing[item.palettePath]||(item.collider?.explicitCollision?[true,true,true]:undefined);
  if(axes)item.resizeAxes=axes;
 }
 return {items:[...builtin.map(i=>({...i,packaged:true})),...imported],index:{version:1,paths},exports,collisionReport};
}
async function catalog(root){
 const hidden=new Set(await require('./hidden-assets').readHiddenAssets(root));
 return (await catalogData(root)).items.map(item=>hidden.has(item.model)?{...item,hidden:true}:item);
}
function bindingsFor(items) {return Object.fromEntries(items.map(i=>[i.id,{source:i.source,model:i.model,stretchable:!!i.stretchable,...(i.resizeAxes?{resizeAxes:i.resizeAxes}:{}),...(i.collider?{collider:i.collider}:{})}]));}
async function generateBuiltins(root) {
 const folder={ClassName:'Folder',Children:builtinCatalog().map(i=>({Name:i.model.split('/').at(-1),ClassName:'Model',Children:[{Name:'Geometry',ClassName:'Part',Properties:{Size:i.size,Position:[0,i.size[1]/2,0],Shape:i.shape,Material:i.material,Color:i.color.map(v=>v/255),Anchored:true,CanCollide:false,CanQuery:false,CanTouch:false}}]}))};
 await fs.mkdir(path.join(root,'assets/builtin'),{recursive:true});
 await fs.writeFile(path.join(root,'assets/builtin/catalog.model.json'),JSON.stringify(folder,null,2)+'\n');
}
module.exports={catalog,catalogData,builtinCatalog,bindingsFor,generateBuiltins,nativeExports};
