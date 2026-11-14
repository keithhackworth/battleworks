'use strict';
const fs=require('node:fs/promises');
const path=require('node:path');
const {createHash}=require('node:crypto');
const {entriesFor}=require('../world/asset-path');
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
function builtinCatalog() {return builtins.map(([id,name,category,size,shape,material,color,solid,destructible])=>({id:`builtin.${id}`,name,category,source:`builtin/${id}.glb`,model:`Builtin/BW_${id}`,size,shape,material,color,defaultScale:1,solid,destructible,hp:100,collider:{widthFraction:1,depthFraction:1,heightFraction:1},...(id==='water'||id==='mud'?{zone:id==='water'?'Water':'Mud'}:{})}));}
async function nativeExports(directory,prefix='') {
 const result=[];
 for(const entry of (await fs.readdir(directory,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
  const relative=prefix+entry.name;
  if(entry.isSymbolicLink())throw new Error(`Asset symlinks are unsupported: ${relative}`);
  if(entry.isDirectory())result.push(...await nativeExports(path.join(directory,entry.name),relative+'/'));
  else if(/\.rbxmx?$/i.test(entry.name))result.push({path:relative.replace(/\.rbxmx?$/i,''),file:path.join(directory,entry.name)});
 }
 const seen=new Set();for(const item of result){if(seen.has(item.path))throw new Error(`Duplicate model export '${item.path}'`);seen.add(item.path);}return result;
}
async function catalog(root) {
 const bindings=JSON.parse(await fs.readFile(path.join(root,'worlds/roblox-assets.json'),'utf8'));
 const exports=await nativeExports(path.join(root,'assets/roblox'));
 const packaged=new Set(exports.map(e=>e.path));const registered=entriesFor(bindings),known=new Set(registered.map(e=>e.model));
 const imported=registered.map(e=>{
  const b=bindings[e.id];return {id:`asset.${e.id}`,name:b.displayName||e.model.split('/').at(-1),category:b.category||e.model.split('/').slice(0,-1).join(' / ')||(/tree/i.test(e.id)?'Trees & vegetation':/fence/i.test(e.id)?'Walls & fences':'Decorations'),source:e.source,model:e.model,defaultScale:45,size:b.size||null,solid:b.solid??!!e.collider,destructible:b.destructible??/tree/i.test(e.id),hp:150,collider:e.collider||null,packaged:packaged.has(e.model)};
 });
 for(const entry of exports)if(!known.has(entry.path))imported.push({id:'asset.'+createHash('sha256').update(entry.path).digest('hex').slice(0,16),name:entry.path.split('/').at(-1),category:entry.path.split('/').slice(0,-1).join(' / ')||'Decorations',source:entry.path,model:entry.path,defaultScale:45,size:null,solid:false,destructible:false,hp:100,collider:{widthFraction:1,depthFraction:1,heightFraction:1},packaged:true});
 return [...builtinCatalog().map(i=>({...i,packaged:true})),...imported];
}
function bindingsFor(items) {return Object.fromEntries(items.map(i=>[i.id,{source:i.source,model:i.model,...(i.collider?{collider:i.collider}:{})}]));}
async function generateBuiltins(root) {
 const folder={ClassName:'Folder',Children:builtinCatalog().map(i=>({Name:i.model.split('/').at(-1),ClassName:'Model',Children:[{Name:'Geometry',ClassName:'Part',Properties:{Size:i.size,Position:[0,i.size[1]/2,0],Shape:i.shape,Material:i.material,Color:i.color.map(v=>v/255),Anchored:true,CanCollide:false,CanQuery:false,CanTouch:false}}]}))};
 await fs.mkdir(path.join(root,'assets/builtin'),{recursive:true});
 await fs.writeFile(path.join(root,'assets/builtin/catalog.model.json'),JSON.stringify(folder,null,2)+'\n');
}
module.exports={catalog,builtinCatalog,bindingsFor,generateBuiltins,nativeExports};
