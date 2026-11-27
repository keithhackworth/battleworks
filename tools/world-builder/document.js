'use strict';
const {compileWorld,serialize}=require('../world/compiler');
const {studioPlacements}=require('../world/studio-placement');
const {bindingsFor}=require('./catalog');
const {resolveAsset}=require('../world/asset-path');
const {createHash}=require('node:crypto');
const Geometry=require('./geometry');
const {multiply,trs}=require('../world/transform');
const Materials=['Grass','Concrete','Sand','Slate','Ice','Mud','Asphalt','WoodPlanks'];
const MaxObjects=512;
const MinTerrainHeight=-96,MaxTerrainHeight=500,TerrainUnit=8,WaterOffset=1024;
const own=(o,k)=>Object.hasOwn(o,k);
function fail(where,message){throw new Error(`${where}: ${message}`);}
function keys(o,allowed,where){if(!o||typeof o!=='object'||Array.isArray(o))fail(where,'expected object');for(const k of Object.keys(o))if(!allowed.includes(k))fail(`${where}.${k}`,'unsupported property');}
function number(v,min,max,where){if(typeof v!=='number'||!Number.isFinite(v)||v<min||v>max)fail(where,`expected finite number in [${min},${max}]`);return v;}
function vector(v,n,min,max,where){if(!Array.isArray(v)||v.length!==n)fail(where,`expected ${n} numbers`);v.forEach((x,i)=>number(x,min,max,`${where}[${i}]`));return [...v];}
function id(v,where){if(typeof v!=='string'||!/^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/.test(v)||v==='default')fail(where,'use 1–64 letters/digits/_/-, starting with a letter; default is reserved');return v;}
function text(v,max,where){if(typeof v!=='string'||v.length>max||!v.trim())fail(where,`expected nonempty text, at most ${max} characters`);return v;}
function bool(v,where){if(typeof v!=='boolean')fail(where,'expected boolean');return v;}
function attachedPose(parent,link){
 const pose=multiply(trs(parent.position,parent.rotation),trs(link.position,link.rotation));
 const cosine=Math.hypot(pose[9],pose[10]);
 const angles=[cosine>1e-6?Math.atan2(-pose[9],pose[10]):Math.atan2(pose[6],pose[5]),
  Math.atan2(pose[8],cosine),cosine>1e-6?Math.atan2(-pose[4],pose[0]):0];
 return {position:pose.slice(12,15),rotation:angles.map(n=>(n*180/Math.PI+360)%360)};
}
function fresh(worldId='new_world',name='New World') {return {schemaVersion:2,id:worldId,name,description:'',settings:{width:230,depth:230,ground:{material:'Grass',color:[100,112,86]},boundary:true},objects:[],spawns:[{id:'boomer_spawn',tank:'Boomer',position:[-22,0,34.5],heading:90},{id:'rattler_spawn',tank:'Rattler',position:[22,0,34.5],heading:270}],gameplay:{}};}
function validate(input,items){
 // HttpService encodes an empty Luau table as []; normalize only this reserved empty object.
 if(input && Array.isArray(input.gameplay) && input.gameplay.length===0)input={...input,gameplay:{}};
 keys(input,['schemaVersion','id','name','description','settings','objects','spawns','gameplay'],'world');
 if(input.schemaVersion!==2)fail('schemaVersion','expected 2; import legacy worlds through migration');
 id(input.id,'id');text(input.name,100,'name');if(typeof input.description!=='string'||input.description.length>2000)fail('description','expected text <=2000 characters');
 keys(input.settings,['width','depth','ground','boundary','terrain','tunnels'],'settings');
 const {width,depth,ground}=input.settings;
 for(const [k,n] of [['width',width],['depth',depth]]){number(n,25,2000,`settings.${k}`);if(n%1)fail(`settings.${k}`,'expected integer studs');}
 if (input.settings.terrain !== undefined) {
  const terrain=input.settings.terrain;
  keys(terrain,['version','columns','rows','heights','paint','water','traction','tractionCells'],'settings.terrain');
  if(terrain.traction!==undefined){
   keys(terrain.traction,['Grass','Mud','Snow','Ice'],'settings.terrain.traction');
   for(const percent of Object.values(terrain.traction))if(!Number.isFinite(percent)||percent<0||percent>100)fail('settings.terrain.traction','traction must be between 0 and 100 percent');
  }
  const grid=n=>Math.max(4,Math.min(36,Math.ceil(n/6)));
  if (terrain.version!==1 || terrain.columns!==grid(width) || terrain.rows!==grid(depth)) fail('settings.terrain','grid does not match map dimensions');
  const count=(terrain.columns+1)*(terrain.rows+1);
  if (!Array.isArray(terrain.heights) || terrain.heights.length!==count) fail('settings.terrain.heights','incorrect sample count');
  for (const value of terrain.heights) if (!Number.isInteger(value) || value<MinTerrainHeight*TerrainUnit || value>MaxTerrainHeight*TerrainUnit) fail('settings.terrain.heights','invalid height sample');
  for (const layer of ['paint','water']) if (Object.hasOwn(terrain,layer)) {
   const values=terrain[layer];
   if (!Array.isArray(values) || values.length!==terrain.columns*terrain.rows) fail(`settings.terrain.${layer}`,'incorrect cell count');
   for (const value of values) if (!Number.isInteger(value) || (value!==0 &&
    (layer==='paint' ? value<1 || value>5 : value<WaterOffset+MinTerrainHeight*TerrainUnit || value>WaterOffset+MaxTerrainHeight*TerrainUnit))) fail(`settings.terrain.${layer}`,'invalid cell');
  }
  if (Object.hasOwn(terrain,'tractionCells')) {
   const values=terrain.tractionCells;
   if (!Array.isArray(values)||values.length!==terrain.columns*terrain.rows) fail('settings.terrain.tractionCells','incorrect cell count');
   for (const [index,percent] of values.entries()) {
    if (percent!==-1&&(!Number.isFinite(percent)||percent<0||percent>100||![1,2,3,4].includes(terrain.paint?.[index]))) {
     fail('settings.terrain.tractionCells','expected an inherited cell or traction from 0 to 100 on a tunable painted material');
    }
   }
  }
 }
 bool(input.settings.boundary,'settings.boundary');
 if(!input.settings.boundary)fail('settings.boundary','open boundaries are not supported by current tank physics');
 if(input.settings.tunnels!==undefined){
  const tunnels=input.settings.tunnels;
  if(!input.settings.terrain||!Array.isArray(tunnels)||tunnels.length>8)fail('settings.tunnels','expected authored terrain and up to eight tunnels');
  for(const [i,tunnel] of tunnels.entries()){
   const at=`settings.tunnels[${i}]`;
   keys(tunnel,['a','b','diameter','traction'],at);
   const diameter=number(tunnel.diameter,12,48,at+'.diameter');
   number(tunnel.traction,0,100,at+'.traction');
   for(const point of [tunnel.a,tunnel.b]){
    vector(point,3,-2000,2000,at);
    if(Math.abs(point[0])+diameter/2+1>width/2||Math.abs(point[2])+diameter/2+1>depth/2||point[1]<MinTerrainHeight||point[1]>MaxTerrainHeight)fail(at,'portal outside clear world dimensions');
   }
   const length=Math.hypot(tunnel.a[0]-tunnel.b[0],tunnel.a[2]-tunnel.b[2]);
   if(length<12||Math.abs(tunnel.a[1]-tunnel.b[1])>length*.35)fail(at,'portals must be separated by 12 studs with a grade of at most 35%');
  }
 }
 keys(ground,['material','color'],'settings.ground');if(!Materials.includes(ground.material))fail('settings.ground.material','unsupported material');vector(ground.color,3,0,255,'settings.ground.color');
 keys(input.gameplay,[],'gameplay');
 if(!Array.isArray(input.objects)||input.objects.length>MaxObjects)fail('objects',`expected array of up to ${MaxObjects} objects`);
 const catalog=new Map(items.map(i=>[i.id,i])),ids=new Set();
 const objects=input.objects.map((o,index)=>{
  const at=`objects[${index}] (${o?.id||'?'})`;keys(o,['id','type','asset','position','rotation','scale','stretch','solid','destructible','hp','bounds','motion','spin','regenerates','regenerationDelay','traction','sound','attachment'],at);
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
  if(o.stretch!==undefined){
   vector(o.stretch,3,.001,1000,`${at}.stretch`);
   if(type.zone||(!type.stretchable&&!type.resizeAxes))fail(at,'Resize requires a native block or an opted-in imported asset');
   if(!type.stretchable&&o.stretch.some((n,axis)=>n!==1&&!type.resizeAxes[axis]))fail(at,'Resize is disabled on that local axis');
  }
  if(type.zone&&(o.position[1]!==0||o.rotation[0]%360!==0||o.rotation[2]%360!==0))fail(at,'water/mud regions must stay level at ground height');
  if(Math.abs(o.position[0])>width/2||Math.abs(o.position[2])>depth/2)fail(at,'object center outside world bounds');
  if(own(o,"regenerates"))bool(o.regenerates,at+".regenerates");
  if(own(o,'traction')){
   if(!type.collider||type.zone||(!type.collider.explicitCollision&&(!type.id.startsWith('builtin.')||['builtin.decoration','builtin.sphere'].includes(type.id))))fail(at+'.traction','asset has no eligible collision surface');
   number(o.traction,0,100,at+'.traction');
  }
  if(own(o,"regenerationDelay"))number(o.regenerationDelay,0,3600,at+".regenerationDelay");
  bool(o.solid,`${at}.solid`);bool(o.destructible,`${at}.destructible`);number(o.hp,1,100000,`${at}.hp`);
  if((o.solid||o.destructible)&&!type.collider)fail(at,'asset has no collider; configure its registry entry before enabling gameplay collision');
  const bounds=o.bounds||type.size;if(!bounds)fail(`${at}.bounds`,'asset dimensions must be measured from its Studio template');vector(bounds,3,.001,10000,`${at}.bounds`);
  let pose;
  if(type.soundBlock){
   if(o.solid||o.destructible)fail(at,'Sound Blocks must be non-solid and indestructible');
   const audio=o.sound,loc=at+'.sound';
   const limits={interval:[.1,3600],cooldown:[0,3600],volume:[0,10],speed:[.1,4],minDistance:[0,1000],maxDistance:[1,2000]};
   keys(audio,['effect','activation','playback','rollOff','filter','origin','targets','trail',...Object.keys(limits)],loc);
   if((type.model==='Builtin/BW_paint_audio')!==own(audio,'trail'))fail(loc,'Paint Audio requires a painted trail');
   if(own(audio,'trail')){
    if(!Array.isArray(audio.trail)||audio.trail.length<1||audio.trail.length>2048)fail(loc+'.trail','expected 1–2048 points');
    audio.trail.forEach((p,i)=>vector(p,3,-8192,8192,loc+'.trail['+i+']'));
   }
   if(typeof audio.effect!=='string'||!/^(?:[A-Za-z0-9][A-Za-z0-9_-]{0,159})?$/.test(audio.effect))fail(loc+'.effect','invalid catalog key');
   for(const [key,options] of Object.entries({activation:['Always','Entry','Exit','Occupied'],playback:['Once','Loop','Repeat'],rollOff:['Inverse','Linear','LinearSquare','InverseTapered'],filter:['Tanks','Moving','Both','Specific','Terrain'],origin:['Block','Trigger']})){
    const optional=key==='filter'||key==='origin';
    if(!(optional&&!own(audio,key))&&!options.includes(audio[key]))fail(loc+'.'+key,'invalid selection');
   }
   for(const [key,[min,max]] of Object.entries(limits))number(audio[key],min,max,loc+'.'+key);
   if(audio.maxDistance<audio.minDistance)fail(loc,'maximum distance must be at least the minimum');
   if(own(audio,'targets')){
    if(!Array.isArray(audio.targets)||audio.targets.length>32||new Set(audio.targets).size!==audio.targets.length)fail(loc+'.targets','expected up to 32 unique placed IDs');
    audio.targets.forEach(target=>id(target,loc+'.targets'));
   }
   if(own(o,'attachment')){
    const link=o.attachment;
    keys(link,['parent','position','rotation'],at+'.attachment');
    id(link.parent,at+'.attachment.parent');
    vector(link.position,3,-8000,8000,at+'.attachment.position');
    vector(link.rotation,3,-8000,8000,at+'.attachment.rotation');
    const parent=input.objects.find(candidate=>candidate?.id===link.parent);
    if(!parent||['Builtin/BW_sound_block','Builtin/BW_paint_audio'].includes(parent.asset)||['builtin.sound_block','builtin.paint_audio'].includes(parent.type)||parent.attachment)fail(at+'.attachment','missing or invalid parent');
    vector(parent.position,3,-2000,2000,at+'.attachment.parent position');
    vector(parent.rotation,3,-360000,360000,at+'.attachment.parent rotation');
    pose=attachedPose(parent,link);
   }
  }else if(own(o,'sound')||own(o,'attachment'))fail(at,'only Sound Blocks support sound or attachment');
  if(own(o,'spin')){
   if(type.zone)fail(at,'terrain regions cannot rotate');
   const atSpin=at+'.spin';
   keys(o.spin,['axis','speed','pause','space','swing'],atSpin);
   if(own(o.spin,'space')&&!['local','world'].includes(o.spin.space))fail(atSpin+'.space','expected local or world');
   vector(o.spin.axis,3,-1,1,atSpin+'.axis');
   number(o.spin.speed,1,360,atSpin+'.speed');
   number(o.spin.pause,0,3600,atSpin+'.pause');
   if(own(o.spin,'swing'))number(o.spin.swing,1,360,atSpin+'.swing');
  }
  if(own(o,'motion')){
   if(type.zone)fail(at,'terrain regions cannot move');
   const m=o.motion,location=at+'.motion';
   keys(m,['points','speed','pause','face','enabled'],location);
   number(m.speed,1,60,location+'.speed');number(m.pause,0,10,location+'.pause');
   bool(m.face,location+'.face');bool(m.enabled,location+'.enabled');
   if(!Array.isArray(m.points)||m.points.length<2||m.points.length>32)fail(location,'expected 2–32 waypoints');
   for(const [i,point] of m.points.entries()){
    vector(point,3,-4000,4000,location+'.points');
    if(point.some((n,j)=>Math.abs(n+(pose?.position||o.position)[j])>[width/2,2000,depth/2][j]))fail(location,'waypoint crosses the world boundary');
    if(i&&Math.hypot(...point.map((n,j)=>n-m.points[i-1][j]))<.05)fail(location,'consecutive waypoints must be distinct');
   }
  }
  const result={...structuredClone(o),...pose,type:type.id,asset:type.model,bounds:[...bounds]};const b=Geometry.box(result);
  if(b.top>2000||b.bottom< -2000)fail(at,'object height exceeds [-2000,2000]');
  const [ex,,ez]=b.extents;
  if(Math.abs(b.x)+ex>width/2+.001||Math.abs(b.z)+ez>depth/2+.001)fail(at,'object footprint crosses world boundary');
  return result;
 });
 if(!Array.isArray(input.spawns)||input.spawns.length>5)fail('spawns','up to five numbered starting areas are supported');
 const numbered=input.spawns.length===0||input.spawns[0].slot!==undefined;
 if(!numbered&&input.spawns.length!==2)fail('spawns','legacy worlds require two tank spawns');
 const seen=new Set();const spawns=input.spawns.map((p,index)=>{
  const at=`spawns[${index}]`;keys(p,['id','tank','slot','position','heading'],at);id(p.id,at+'.id');if(ids.has(p.id))fail(at,'duplicate object/spawn ID');ids.add(p.id);
  const key=numbered?p.slot:p.tank;
  if((numbered?(!Number.isInteger(key)||key<1||key>5):!['Boomer','Rattler'].includes(key))||seen.has(key))fail(at,'duplicate or invalid starting position');seen.add(key);
  vector(p.position,3,-2000,2000,at+'.position');number(p.heading,-360000,360000,at+'.heading');
  const margin=numbered?20:7;
  if(p.position[1]!==0||Math.abs(p.position[0])>width/2-margin||Math.abs(p.position[2])>depth/2-margin)fail(at,'starting area must fit on clear ground inside boundary');
  for(const o of objects)if(o.solid){const type=catalog.get(o.type),f=type.collider;const box=Geometry.box(o,[f.widthFraction,f.heightFraction,f.depthFraction]);if((f.fit==='faces'?Geometry.faces(box,f.faces,f.bases,f.walls):Geometry.cells(box,f.boxes)).some(cell=>Geometry.spawnHits(p.position,cell,numbered?20:6)))fail(at,`spawn intersects solid '${o.id}'`);}
  return {...structuredClone(p),heading:((p.heading%360)+360)%360};
 });
 for(let i=0;i<spawns.length;i++)for(let j=0;j<i;j++)if(Math.hypot(spawns[i].position[0]-spawns[j].position[0],spawns[i].position[2]-spawns[j].position[2])<(numbered?40:14))fail('spawns','starting areas overlap');
 return {...structuredClone(input),objects:objects.sort((a,b)=>a.id.localeCompare(b.id)),spawns:spawns.sort((a,b)=>numbered?a.slot-b.slot:a.tank.localeCompare(b.tank))};
}
function compileDocument(input,items){
 const document=validate(input,items),byId=new Map(items.map(i=>[i.id,i]));
 const definitions={},instances=[];
 document.objects.forEach(o=>{const i=byId.get(o.type);const ref='asset_'+createHash('sha256').update(i.model).digest('hex').slice(0,16);definitions[ref]={type:'model',asset:i.model};instances.push({id:o.id,ref,position:o.position,rotation:o.rotation,scale:o.stretch?o.stretch.map(n=>n*o.scale):o.scale,influences:{physical:{movable:false,destructible:o.destructible,hp:o.hp},movement:{collision:o.solid?'solid':'none',traversable:!o.solid}}});});
 const manifest=compileWorld({version:1,id:document.id,name:document.name,seed:0,definitions,instances},{},{assetBindings:bindingsFor(items)});
 const authored=new Map(document.objects.map(o=>[o.id,o]));
 for(const object of manifest.objects)for(const key of ["motion","spin","regenerates","regenerationDelay","traction","sound","attachment"]){
  const source=authored.get(object.id);
  if(source&&own(source,key))object[key]=source[key];
 }
 // Empty worlds are valid: ground and spawns are enough for a battle.
 manifest.builderSettings={...document.settings,spawns:document.spawns,zones:document.objects.filter(o=>byId.get(o.type).zone).map(o=>({kind:byId.get(o.type).zone,x:o.position[0],z:o.position[2],rx:o.bounds[0]*o.scale/2,rz:o.bounds[2]*o.scale/2,speed:byId.get(o.type).zone==='Water'?.9:.75}))};
 return {document,manifest};
}
function migrate(manifest,items,newId){
 const doc=fresh(newId,manifest.name+' (editable copy)');const bindings=bindingsFor(items);
 if (manifest.builderSettings) {
  const {width,depth,ground,boundary,terrain,tunnels,spawns}=manifest.builderSettings;
  doc.settings=structuredClone({width,depth,ground,boundary,...(terrain?{terrain}:{}),...(tunnels?{tunnels}:{})});
  doc.spawns=structuredClone(spawns);
 }
 const placements=manifest.objects.length?studioPlacements(manifest,bindings):[];
 if(!placements)fail('migration','legacy world contains unmapped assets, unsupported influences or nonuniform transforms');
 const used=new Set();doc.objects=placements.map((p,index)=>{
  const item=items.find(i=>i.model===p.model);let name=p.id.replace(/[^a-zA-Z0-9_-]/g,'_');if(!/^[a-zA-Z]/.test(name))name='object_'+name;name=name.slice(0,55);if(used.has(name))name+='_'+index;used.add(name);
  return {id:name,type:item.id,asset:item.model,position:p.position,rotation:p.rotation,scale:p.scale,...(p.motion?{motion:p.motion}:{}),...(p.spin?{spin:p.spin}:{}),...(own(p,"traction")?{traction:p.traction}:{}),...(p.sound?{sound:p.sound}:{}),...(p.attachment?{attachment:p.attachment}:{}),...(p.stretch?{stretch:p.stretch}:{}),solid:p.interaction?.solid||false,destructible:p.interaction?.destructible||false,hp:p.interaction?.hp??100,...(p.interaction?.regenerates!==undefined?{regenerates:p.interaction.regenerates}:{}),...(p.interaction?.regenerationDelay!==undefined?{regenerationDelay:p.interaction.regenerationDelay}:{}),...(item.size?{bounds:item.size}:{})};
 });
 // Bounds for imported assets are measured when the plugin resolves templates.
 return doc;
}
module.exports={fresh,validate,compileDocument,migrate,Materials,MaxObjects,serialize};
