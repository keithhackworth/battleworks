'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs/promises');const os=require('node:os');const path=require('node:path');
const {builtinCatalog}=require('../tools/world-builder/catalog');
const {fresh,validate,compileDocument,migrate,serialize}=require('../tools/world-builder/document');
const {Store}=require('../tools/world-builder/store');const {createServer}=require('../tools/world-builder/server');
const items=builtinCatalog();
test('sculpted terrain survives offline serialization, compilation, and migration',()=>{
 const d=fresh('terrain_world');
 const heights=Array(37*37).fill(0);heights[102]=4000;heights[233]=-156;
 d.settings.terrain={version:1,columns:36,rows:36,heights};
 d.settings.terrain.paint=Array(36*36).fill(5);
 d.settings.terrain.water=Array(36*36).fill(0);d.settings.terrain.water[5]=5024;
 d.settings.terrain.traction={Ice:5.25,Mud:0,Grass:55,Snow:100};
 const built=compileDocument(JSON.parse(serialize(d)),items);
 assert.deepEqual(built.manifest.builderSettings.terrain,d.settings.terrain);
 assert.deepEqual(migrate(built.manifest,items,'terrain_copy').settings.terrain,d.settings.terrain);
 const invalid=structuredClone(d);invalid.settings.terrain.traction.Ice=101;
 assert.throws(()=>compileDocument(invalid,items),/traction/);
 d.settings.terrain.heights[102]=4001;
 assert.throws(()=>compileDocument(d,items),/invalid height sample/);
});
function object(extra={}){return {id:'obstacle_1',type:'builtin.block',position:[0,0,-25],rotation:[0,30,0],scale:1,solid:true,destructible:false,hp:100,...extra};}
async function fixture(t){const root=await fs.mkdtemp(path.join(os.tmpdir(),'bw-builder-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));await fs.mkdir(path.join(root,'assets/roblox'),{recursive:true});await fs.mkdir(path.join(root,'worlds'),{recursive:true});await fs.writeFile(path.join(root,'worlds/roblox-assets.json'),'{}');const store=new Store(root);await store.init();return store;}
test('builder catalog has stable reusable types and sensible tree/fence behaviors',()=>{assert.equal(new Set(items.map(i=>i.id)).size,items.length);assert.ok(items.length>=10);assert.equal(items.find(i=>i.id==='builtin.tree').destructible,true);assert.equal(items.find(i=>i.id==='builtin.wall').solid,true);});
test('document serializes deterministically and compiles into existing v1 placement manifests',()=>{const d=fresh();d.objects=[object(),object({id:'a',position:[30,0,-20]})];const built=compileDocument(d,items);assert.equal(built.manifest.objects.length,2);assert.equal(built.manifest.objects[0].id,'a');assert.deepEqual(built.document.objects[0].bounds,[8,5,8]);assert.equal(serialize(built),serialize(compileDocument(JSON.parse(serialize(d)),items)));assert.equal(built.manifest.builderSettings.width,230);assert.equal(built.manifest.builderSettings.spawns.length,2);});
test('empty world remains playable and retains ground, bounds and spawns',async t=>{const store=await fixture(t),result=await store.save(fresh('empty','Empty'),true);assert.equal(result.catalog.Children.find(e=>e.Name==='empty').Children.find(e=>e.Name==='Status').Properties.Value,'asset-dependent');const record=result.catalog.Children.find(e=>e.Name==='empty');assert.ok(record.Children.find(e=>e.Name==='BuilderSettings'));assert.deepEqual(await store.get('empty'),result.document);});
test('invalid data errors identify properties, unknown types and spawn collisions',()=>{
 const cases=[['version',d=>d.schemaVersion=99,/schemaVersion/],['coordinate',d=>d.objects=[object({position:[NaN,0,0]})],/position/],['missing type',d=>d.objects=[object({type:'unknown'})],/unknown catalog/],['duplicate',d=>d.objects=[object(),object()],/duplicate/],['ground',d=>d.settings.ground.material='Lava',/material/],['bounds',d=>d.settings.width=2,/width/],['elevation',d=>d.objects=[object({position:[0,Infinity,-25]})],/position/],['spawn',d=>d.spawns[0].position=[0,0,-25],/intersects/],['excess starts',d=>d.spawns=Array(6).fill(d.spawns[0]),/five/],['outside',d=>d.objects=[object({position:[120,0,0]})],/outside/],['edge',d=>d.objects=[object({position:[113,0,0]})],/footprint/],['unknown field',d=>d.objects=[object({script:'run'})],/unsupported/]];
 for(const [name,mutate,pattern]of cases){const d=fresh();d.objects=[object()];mutate(d);assert.throws(()=>validate(d,items),pattern,name);}
});
test('unknown collision capabilities and missing model dimensions are explicit errors',()=>{const native={id:'asset.unknown',source:'u.glb',model:'u',size:null,collider:null};const d=fresh();d.objects=[object({type:native.id})];assert.throws(()=>validate(d,[...items,native]),/no collider/);d.objects[0].solid=false;assert.throws(()=>validate(d,[...items,native]),/measured/);});
test('spawn validation uses rotated footprints and world settings',()=>{const d=fresh();d.objects=[object({position:[-22,0,34.5],rotation:[0,90,0]})];assert.throws(()=>validate(d,items),/spawns\[0\].*obstacle_1/);d.objects[0].solid=false;assert.equal(validate(d,items).objects.length,1);d.spawns[1].position=[-22,0,34.5];assert.throws(()=>validate(d,items),/overlap/);});
test('surface zones compile to existing water/mud influence data',()=>{const d=fresh();d.objects=[object({type:'builtin.water',solid:false,position:[0,0,-25]})];const {manifest}=compileDocument(d,items);assert.deepEqual(manifest.builderSettings.zones[0],{kind:'Water',x:0,z:-25,rx:9,rz:9,speed:.9});});
test('legacy migration reuses resolved assets and gives stable unique editable IDs',()=>{const d=fresh('original');d.objects=[object()];const manifest=compileDocument(d,items).manifest;const copy=migrate(manifest,items,'original_edit');assert.equal(copy.id,'original_edit');assert.equal(copy.objects[0].type,'builtin.block');assert.deepEqual(copy.objects[0].position,d.objects[0].position);assert.equal(validate(copy,items).objects[0].solid,true);manifest.objects[0].asset='missing.glb';assert.throws(()=>migrate(manifest,items,'bad'),/unmapped/);});
test('save, reopen, rename, duplicate, select, export and delete round-trip',async t=>{const store=await fixture(t);const d=fresh('arena_one','Arena One');d.objects=[object()];await store.save(d,true);let reopened=await store.get('arena_one');reopened.name='Renamed';await store.save(reopened);assert.equal((await store.get(d.id)).name,'Renamed');reopened.id='arena_two';await store.save(reopened,true);assert.equal((await store.list()).length,2);assert.equal(JSON.parse(await fs.readFile(path.join(store.root,'worlds/selected-world.model.json'))).Properties.Value,'arena_two');await assert.rejects(store.remove('arena_two','wrong'),/confirmation/);await store.remove('arena_two','arena_two');assert.equal((await store.list()).length,1);assert.equal(JSON.parse(await fs.readFile(path.join(store.root,'worlds/selected-world.model.json'))).Properties.Value,'');await store.rebuild();assert.equal((await store.get(d.id)).name,'Renamed');});
test('invalid saves are non-destructive and traversal cannot escape the document directory',async t=>{const store=await fixture(t);await store.save(fresh('safe'));const before=await fs.readFile(store.file('safe'),'utf8');const bad=fresh('safe');bad.spawns=[bad.spawns[0]];await assert.rejects(store.save(bad),/spawns/);assert.equal(await fs.readFile(store.file('safe'),'utf8'),before);await assert.rejects(store.get('../bad'),/Invalid world ID/);await assert.rejects(store.remove('../bad','../bad'),/Invalid world ID/);});
test('concurrent saves are serialized without dropping world registrations',async t=>{const store=await fixture(t);await Promise.all([store.save(fresh('first')),store.save(fresh('second'))]);const catalog=JSON.parse(await fs.readFile(path.join(store.root,'worlds/studio-worlds.model.json')));assert.deepEqual(catalog.Children.map(e=>e.Name),['default','first','second']);});
test('loopback bridge authenticates writes, rejects browser origins and supports editor CRUD',async t=>{const store=await fixture(t);const server=createServer(store,{token:'test-token'});await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>new Promise(r=>server.close(r)));const url='http://127.0.0.1:'+server.address().port;
 const headers={'X-BW-Token':'test-token','Content-Type':'application/json'};
 assert.equal((await fetch(url+'/worlds')).status,403);assert.equal((await fetch(url+'/session',{headers:{Origin:'http://evil.test'}})).status,403);assert.equal((await (await fetch(url+'/session')).json()).token,'test-token');
 let response=await fetch(url+'/save',{method:'POST',headers,body:JSON.stringify({document:fresh('api_world'),select:true})});assert.equal(response.status,200);assert.equal((await response.json()).selected,'api_world');assert.equal((await (await fetch(url+'/worlds',{headers})).json()).worlds[0].id,'api_world');assert.equal((await (await fetch(url+'/export?id=api_world',{headers})).json()).schemaVersion,2);
 response=await fetch(url+'/delete',{method:'POST',headers,body:JSON.stringify({id:'api_world',confirmation:'api_world'})});assert.equal(response.status,200);
});

test('publish is explicit, persisted, and removed cleanly with its world',async t=>{const store=await fixture(t);await store.save(fresh('published'));assert.deepEqual(await store.publish('published'),{published:'published'});assert.equal(JSON.parse(await fs.readFile(path.join(store.root,'worlds/published-world.model.json'))).Properties.Value,'published');await store.remove('published','published');assert.equal(JSON.parse(await fs.readFile(path.join(store.root,'worlds/published-world.model.json'))).Properties.Value,'');});

test('Studio catalog discovery registers complete model paths without merging duplicate basenames',async t=>{const store=await fixture(t);await store.discoverAssets([{path:'Buildings/Houses/Fence',size:[2,4,1]},{path:'Structures/Fences/Fence',size:[4,3,1]}]);const items=await store.items();const fences=items.filter(i=>i.name==='Fence');assert.equal(fences.length,2);assert.equal(new Set(fences.map(i=>i.id)).size,2);assert.deepEqual(fences.map(i=>i.model).sort(),['Buildings/Houses/Fence','Structures/Fences/Fence']);await assert.rejects(store.discoverAssets([{path:'../Fence',size:[1,1,1]}]),/Invalid asset path/);await assert.rejects(store.discoverAssets([{path:'A/Fence',size:[1,1,1]},{path:'A/Fence',size:[1,1,1]}]),/Duplicate Studio asset path/);});

test('duplicate/import creation cannot silently overwrite an existing world',async t=>{const store=await fixture(t);await store.save(fresh('existing','Original'));await assert.rejects(store.save(fresh('existing','Replacement'),false,true),/already exists/);assert.equal((await store.get('existing')).name,'Original');});

test('migration accepts upright decorative yaw beyond 90 degrees without inventing roll',()=>{const d=fresh('old');d.objects=[object({solid:false,rotation:[0,270,0]})];const {manifest}=compileDocument(d,items);const migrated=migrate(manifest,items,'old_edit');assert.ok(Math.abs((migrated.objects[0].rotation[1]+360)%360-270)<1e-6);assert.equal(validate(migrated,items).objects[0].asset,'Builtin/BW_block');});
test('elevated tilted worlds retain all three axes through compile, native placement and migration',()=>{
 const {studioPlacements}=require('../tools/world/studio-placement');const {bindingsFor}=require('../tools/world-builder/catalog');const {trs}=require('../tools/world/transform');
 for(const rotation of [[15,37,-12],[0,270,20],[45,90,0],[-25,135,15]]) {
  const d=fresh('raised_world');d.objects=[object({position:[-30,8,-40],rotation})];
  const result=compileDocument(d,items),p=studioPlacements(result.manifest,bindingsFor(items))[0];
  const expected=trs(d.objects[0].position,rotation,1),actual=trs(p.position,p.rotation,p.scale);
  actual.forEach((n,i)=>assert.ok(Math.abs(n-expected[i])<1e-7));
  const edited=migrate(result.manifest,items,'raised_copy');assert.equal(edited.objects[0].position[1],8);assert.equal(validate(edited,items).objects[0].asset,'Builtin/BW_block');
 }
});
test('tilted full footprints and elevated spawn clearance are validated in 3D',()=>{
 const d=fresh();d.objects=[object({position:[-22,8,34.5]})];assert.equal(validate(d,items).objects[0].position[1],8);
 d.objects[0].position[1]=2;assert.throws(()=>validate(d,items),/spawn.*intersects/);
 d.objects=[object({position:[110,0,-20],rotation:[0,0,60],bounds:[1,20,1]})];assert.throws(()=>validate(d,items),/footprint/);
 d.objects=[object({position:[0,1999,0]})];assert.throws(()=>validate(d,items),/height/);
});
test('water and mud region behavior stays explicitly on the ground',()=>{
 const d=fresh();d.objects=[object({type:'builtin.water',position:[0,2,-25],solid:false})];assert.throws(()=>validate(d,items),/water\/mud.*ground/);
 d.objects[0].position[1]=0;d.objects[0].rotation=[15,0,0];assert.throws(()=>validate(d,items),/water\/mud.*ground/);
});
test('stretch retains independent dimensions through compile and migration',()=>{
 const {studioPlacements}=require('../tools/world/studio-placement');
 const {bindingsFor}=require('../tools/world-builder/catalog');
 const d=fresh();d.objects=[object({stretch:[1,1,3],rotation:[20,90,10]})];
 const compiled=compileDocument(d,items);
 const placements=studioPlacements(compiled.manifest,bindingsFor(items));
 assert.ok(placements);assert.equal(placements[0].scale,1);
 assert.ok(Math.abs(placements[0].stretch[2]-3)<1e-6);
 const copy=migrate(compiled.manifest,items,'stretch_copy');
 assert.ok(Math.abs(copy.objects[0].stretch[2]-3)<1e-6);
 for(const stretch of [[0,1,1],[1,1],[1,1,Infinity],[1,1,1001]])assert.throws(()=>validate({...d,objects:[object({stretch})]},items));
 assert.throws(()=>validate({...d,objects:[object({stretch:[1,1,2],type:'builtin.rock'})]},items),/native block/);
 assert.throws(()=>validate({...d,objects:[object({stretch:[100,1,1]})]},items),/footprint/);
});
test('opted-in bridge resize survives JSON, Studio placement and migration with disabled axes enforced',()=>{
 const {studioPlacements,placementIssue}=require('../tools/world/studio-placement');
 const {bindingsFor}=require('../tools/world-builder/catalog');
 const bridge={...items.find(i=>i.id==='builtin.bridge'),id:'asset.bridge',model:'Forest/rope-bridge',stretchable:false,resizeAxes:[true,false,true]};
 const catalog=[...items,bridge];
 const d=fresh('resized_bridge');
 d.objects=[object({type:bridge.id,asset:bridge.model,scale:1.5,stretch:[2,1,3],rotation:[0,90,0]})];
 const {manifest}=compileDocument(JSON.parse(serialize(d)),catalog);
 const [placement]=studioPlacements(manifest,bindingsFor(catalog));
 assert.deepEqual(placement.resizeAxes,[true,false,true]);
 assert.deepEqual(placement.stretch,[2,1,3]);
 assert.equal(placement.scale,1.5);
 assert.deepEqual(migrate(manifest,catalog,'bridge_copy').objects[0].stretch,[2,1,3]);
 bridge.resizeAxes=[true,false,false];
 assert.match(placementIssue(manifest,bindingsFor(catalog)),/Resize is disabled/);
 assert.throws(()=>compileDocument(d,catalog),/Resize is disabled/);
});
test('numbered three-tank starting areas persist and reserve full ground clearance',()=>{
 const d=fresh();d.spawns=[];
 assert.equal(validate(d,items).spawns.length,0);
 const points=[[-60,0,-60],[0,0,-60],[60,0,-60],[-60,0,60],[60,0,60]];
 d.spawns=points.map((position,i)=>({id:'start_'+(i+1),slot:i+1,position,heading:0}));
 const built=compileDocument(d,items);
 assert.deepEqual(built.manifest.builderSettings.spawns,d.spawns);
 const bad=structuredClone(d);bad.spawns[4].slot=3;assert.throws(()=>validate(bad,items),/invalid starting/);
 bad.spawns=structuredClone(d.spawns);bad.spawns[0].position=[100,0,-60];assert.throws(()=>validate(bad,items),/inside boundary/);
 bad.spawns=structuredClone(d.spawns);bad.objects=[object({position:[-45,0,-60]})];assert.throws(()=>validate(bad,items),/intersects/);
});

test('fitted imported collision cells preserve rotated spawn clearance without changing visual bounds',()=>{
 const Geometry=require('../tools/world-builder/geometry');
 for(const rotation of [[0,0,0],[0,90,0],[15,37,-10]]){
  const o={bounds:[40,20,60],scale:1.5,rotation,position:[10,4,-20]};
  const outer=Geometry.box(o,[1,1,1]);
  const cells=Geometry.cells(outer,[{center:[0,0,0],size:[.25,1,.25]}]);
  assert.equal(cells.length,1);assert.deepEqual(cells[0].size,[15,30,22.5]);
  assert.deepEqual(cells[0].center,outer.center);
  assert.deepEqual(Geometry.cells(outer),[outer],'unprofiled buildings and builtins retain the whole box');
 }
 const outer=Geometry.box({bounds:[80,20,80],scale:1,rotation:[0,90,0],position:[0,0,0]},[1,1,1]);
 const [cell]=Geometry.cells(outer,[{center:[0,0,0],size:[.5,1,.5]}]);
 assert.equal(Geometry.spawnHits([37,0,37],outer,1),true);
 assert.equal(Geometry.spawnHits([37,0,37],cell,1),false);
 assert.equal(Geometry.spawnHits([0,0,0],cell,1),true);
});
test('asset motion persists in authored, compiled and Studio world data',async()=>{
 const d=fresh('motion_world');
 const motion={points:[[0,0,0],[30,0,0],[30,0,10],[0,0,1]],speed:16,pause:.5,face:true,enabled:true};
 d.objects=[{id:'moving',type:'builtin.crate',asset:'Builtin/BW_crate',position:[0,0,-15],rotation:[0,15,0],scale:1,solid:true,destructible:true,hp:100,motion}];
 const {manifest,document}=compileDocument(d,items);
 assert.deepEqual(document.objects[0].motion,motion);
 assert.deepEqual(manifest.objects[0].motion,motion);
 assert.deepEqual(migrate(manifest,items,'motion_copy').objects[0].motion,motion);
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'bw-motion-catalog-'));
 try {
  await fs.writeFile(path.join(root,'motion_world.json'),JSON.stringify(manifest));
  const catalog=await require('../tools/world/catalog').discoverWorlds(root,require('../tools/world-builder/catalog').bindingsFor(items));
  const placement=catalog.Children.find(entry=>entry.Name==='motion_world').Children.find(node=>node.Name==='Placement');
  assert.deepEqual(JSON.parse(placement.Children.find(node=>node.Name==='Motion').Properties.Value),motion);
 } finally {await fs.rm(root,{recursive:true,force:true});}
 motion.points[0][2]=4000;
 assert.throws(()=>validate(d,items),/crosses the world boundary/);
});

test('asset regeneration survives offline compilation and editing',()=>{
 const world=fresh('regeneration_world');
 world.objects=[{id:'crate',type:'builtin.crate',asset:'Builtin/BW_crate',position:[0,0,0],rotation:[0,0,0],scale:1,solid:true,destructible:true,hp:100,regenerates:false,regenerationDelay:12.5}];
 const {manifest}=compileDocument(world,items);
 const object=migrate(manifest,items,'regen_copy').objects[0];
 assert.equal(object.regenerates,false);
 assert.equal(object.regenerationDelay,12.5);
 world.objects[0].regenerationDelay=-1;
 assert.throws(()=>validate(world,items),/regenerationDelay/);
});

test('tunnels retain portal elevations, diameter and traction through compilation and migration',()=>{
 const world=fresh('tunnel_world');
 world.settings.terrain={version:1,columns:36,rows:36,heights:Array(37*37).fill(0)};
 world.settings.tunnels=[{a:[-40,0,0],b:[40,3,0],diameter:18,traction:55}];
 const {manifest}=compileDocument(world,items);
 assert.deepEqual(migrate(manifest,items,'tunnel_copy').settings.tunnels,world.settings.tunnels);
 world.settings.tunnels[0].b[1]=52;
 assert.throws(()=>validate(world,items),/grade/);
});
