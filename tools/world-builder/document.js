'use strict';
const {compileWorld,serialize}=require('../world/compiler');
const {studioPlacements}=require('../world/studio-placement');
const {bindingsFor}=require('./catalog');
const {resolveAsset}=require('../world/asset-path');
const {createHash}=require('node:crypto');
const Geometry=require('./geometry');
const Materials=['Grass','Concrete','Sand','Slate','Ice','Mud','Asphalt','WoodPlanks'];
const MaxObjects=512;
const own=(o,k)=>Object.hasOwn(o,k);
function fail(where,message){throw new Error(`${where}: ${message}`);}
function keys(o,allowed,where){if(!o||typeof o!=='object'||Array.isArray(o))fail(where,'expected object');for(const k of Object.keys(o))if(!allowed.includes(k))fail(`${where}.${k}`,'unsupported property');}
function number(v,min,max,where){if(typeof v!=='number'||!Number.isFinite(v)||v<min||v>max)fail(where,`expected finite number in [${min},${max}]`);return v;}
function vector(v,n,min,max,where){if(!Array.isArray(v)||v.length!==n)fail(where,`expected ${n} numbers`);v.forEach((x,i)=>number(x,min,max,`${where}[${i}]`));return [...v];}
function id(v,where){if(typeof v!=='string'||!/^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/.test(v)||v==='default')fail(where,'use 1–64 letters/digits/_/-, starting with a letter; default is reserved');return v;}
function text(v,max,where){if(typeof v!=='string'||v.length>max||!v.trim())fail(where,`expected nonempty text, at most ${max} characters`);return v;}
function bool(v,where){if(typeof v!=='boolean')fail(where,'expected boolean');return v;}
function fresh(worldId='new_world',name='New World') {return {schemaVersion:2,id:worldId,name,description:'',settings:{width:230,depth:230,ground:{material:'Grass',color:[100,112,86]},boundary:true},objects:[],spawns:[{id:'boomer_spawn',tank:'Boomer',position:[-22,0,34.5],heading:90},{id:'rattler_spawn',tank:'Rattler',position:[22,0,34.5],heading:270}],gameplay:{}};}
function validate(input,items){
 // HttpService encodes an empty Luau table as []; normalize only this reserved empty object.
 if(input && Array.isArray(input.gameplay) && input.gameplay.length===0)input={...input,gameplay:{}};
 keys(input,['schemaVersion','id','name','description','settings','objects','spawns','gameplay'],'world');
 if(input.schemaVersion!==2)fail('schemaVersion','expected 2; import legacy worlds through migration');
 id(input.id,'id');text(input.name,100,'name');if(typeof input.description!=='string'||input.description.length>2000)fail('description','expected text <=2000 characters');
 keys(input.settings,['width','depth','ground','boundary'],'settings');
 const {width,depth,ground}=input.settings;
 for(const [k,n] of [['width',width],['depth',depth]]){number(n,25,2000,`settings.${k}`);if(n%1)fail(`settings.${k}`,'expected integer studs');}
 bool(input.settings.boundary,'settings.boundary');
 if(!input.settings.boundary)fail('settings.boundary','open boundaries are not supported by current tank physics');
 keys(ground,['material','color'],'settings.ground');if(!Materials.includes(ground.material))fail('settings.ground.material','unsupported material');vector(ground.color,3,0,255,'settings.ground.color');
 keys(input.gameplay,[],'gameplay');
 if(!Array.isArray(input.objects)||input.objects.length>MaxObjects)fail('objects',`expected array of up to ${MaxObjects} objects`);
 const catalog=new Map(items.map(i=>[i.id,i])),ids=new Set();
 const objects=input.objects.map((o,index)=>{
  const at=`objects[${index}] (${o?.id||'?'})`;keys(o,['id','type','asset','position','rotation','scale','solid','destructible','hp','bounds'],at);
  id(o.id,`${at}.id`);if(ids.has(o.id))fail(at,'duplicate object ID');ids.add(o.id);
  let type=catalog.get(o.type);
  if(o.asset!==undefined){
    let binding;try{binding=resolveAsset(o.asset,bindingsFor(items));}catch(e){fail(`${at}.asset`,e.message);}
    if(!binding)fail(`${at}.asset`,`missing asset path '${o.asset}'`);
    const resolved=items.find(i=>i.model===binding.model);
    if(type&&type.model!==resolved.model)fail(at,'catalog type and asset path refer to different assets');
    type=resolved;
  }
  if(!type)fail(`${at}.type`,`unknown catalog type '${o.type}'`);
  vector(o.position,3,-2000,2000,`${at}.position`);vector(o.rotation,3,-360000,360000,`${at}.rotation`);number(o.scale,.001,1000,`${at}.scale`);
  if(type.zone&&(o.position[1]!==0||o.rotation[0]%360!==0||o.rotation[2]%360!==0))fail(at,'water/mud regions must stay level at ground height');
  if(Math.abs(o.position[0])>width/2||Math.abs(o.position[2])>depth/2)fail(at,'object center outside world bounds');
  bool(o.solid,`${at}.solid`);bool(o.destructible,`${at}.destructible`);number(o.hp,1,100000,`${at}.hp`);
  if((o.solid||o.destructible)&&!type.collider)fail(at,'asset has no collider; configure its registry entry before enabling gameplay collision');
  const bounds=o.bounds||type.size;if(!bounds)fail(`${at}.bounds`,'asset dimensions must be measured from its Studio template');vector(bounds,3,.001,10000,`${at}.bounds`);
  const result={...structuredClone(o),type:type.id,asset:type.model,bounds:[...bounds]};const b=Geometry.box(result);
  if(b.top>2000||b.bottom< -2000)fail(at,'object height exceeds [-2000,2000]');
  const [ex,,ez]=b.extents;
  if(Math.abs(b.x)+ex>width/2+.001||Math.abs(b.z)+ez>depth/2+.001)fail(at,'object footprint crosses world boundary');
  return result;
 });
 if(!Array.isArray(input.spawns)||input.spawns.length!==2)fail('spawns','exactly one Boomer and one Rattler spawn are required');
 const tanks=new Set();const spawns=input.spawns.map((p,index)=>{
  const at=`spawns[${index}]`;keys(p,['id','tank','position','heading'],at);id(p.id,at+'.id');if(ids.has(p.id))fail(at,'duplicate object/spawn ID');ids.add(p.id);
  if(!['Boomer','Rattler'].includes(p.tank)||tanks.has(p.tank))fail(at,'one unique spawn per tank is required');tanks.add(p.tank);
  vector(p.position,3,-2000,2000,at+'.position');number(p.heading,-360000,360000,at+'.heading');
  if(p.position[1]!==0||Math.abs(p.position[0])>width/2-7||Math.abs(p.position[2])>depth/2-7)fail(at,'spawn must rest on ground at least 7 studs inside boundary');
  for(const o of objects)if(o.solid){const type=catalog.get(o.type),f=type.collider;const box=Geometry.box(o,[f.widthFraction,f.heightFraction,f.depthFraction]);if(Geometry.spawnHits(p.position,box))fail(at,`spawn intersects solid '${o.id}'`);}
  return {...structuredClone(p),heading:((p.heading%360)+360)%360};
 });
 if(Math.hypot(spawns[0].position[0]-spawns[1].position[0],spawns[0].position[2]-spawns[1].position[2])<14)fail('spawns','tank spawns must be at least 14 studs apart');
 return {...structuredClone(input),objects:objects.sort((a,b)=>a.id.localeCompare(b.id)),spawns:spawns.sort((a,b)=>a.tank.localeCompare(b.tank))};
}
function compileDocument(input,items){
 const document=validate(input,items),byId=new Map(items.map(i=>[i.id,i]));
 const definitions={},instances=[];
 document.objects.forEach(o=>{const i=byId.get(o.type);const ref='asset_'+createHash('sha256').update(i.model).digest('hex').slice(0,16);definitions[ref]={type:'model',asset:i.model};instances.push({id:o.id,ref,position:o.position,rotation:o.rotation,scale:o.scale,influences:{physical:{movable:false,destructible:o.destructible,hp:o.hp},movement:{collision:o.solid?'solid':'none',traversable:!o.solid}}});});
 const manifest=compileWorld({version:1,id:document.id,name:document.name,seed:0,definitions,instances},{},{assetBindings:bindingsFor(items)});
 // Empty worlds are valid: ground and spawns are enough for a battle.
 manifest.builderSettings={...document.settings,spawns:document.spawns,zones:document.objects.filter(o=>byId.get(o.type).zone).map(o=>({kind:byId.get(o.type).zone,x:o.position[0],z:o.position[2],rx:o.bounds[0]*o.scale/2,rz:o.bounds[2]*o.scale/2,speed:byId.get(o.type).zone==='Water'?.9:.75}))};
 return {document,manifest};
}
function migrate(manifest,items,newId){
 const doc=fresh(newId,manifest.name+' (editable copy)');const bindings=bindingsFor(items);
 const placements=manifest.objects.length?studioPlacements(manifest,bindings):[];
 if(!placements)fail('migration','legacy world contains unmapped assets, unsupported influences or nonuniform transforms');
 const used=new Set();doc.objects=placements.map((p,index)=>{
  const item=items.find(i=>i.model===p.model);let name=p.id.replace(/[^a-zA-Z0-9_-]/g,'_');if(!/^[a-zA-Z]/.test(name))name='object_'+name;name=name.slice(0,55);if(used.has(name))name+='_'+index;used.add(name);
  return {id:name,type:item.id,asset:item.model,position:p.position,rotation:p.rotation,scale:p.scale,solid:p.interaction?.solid||false,destructible:p.interaction?.destructible||false,hp:p.interaction?.hp??100,...(item.size?{bounds:item.size}:{})};
 });
 // Bounds for imported assets are measured when the plugin resolves templates.
 return doc;
}
module.exports={fresh,validate,compileDocument,migrate,Materials,MaxObjects,serialize};
