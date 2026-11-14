'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const {catalog}=require('../tools/world-builder/catalog');
const {buildEditorCatalog}=require('../tools/build-editor-catalog');
const {fresh,compileDocument}=require('../tools/world-builder/document');
const ROOT=path.resolve(__dirname,'..');
test('packaged in-game catalog is generated from the existing asset catalog',async()=>{
 const metadata=JSON.parse(await fs.readFile(path.join(ROOT,'assets/editor-catalog.model.json'),'utf8'));
 assert.equal(metadata.ClassName,'StringValue');
 assert.deepEqual(JSON.parse(metadata.Properties.Value),await catalog(ROOT));
 const project=JSON.parse(await fs.readFile(path.join(ROOT,'default.project.json'),'utf8'));
 assert.equal(project.tree.ServerStorage.BattleWorksStudio.EditorAssetCatalog.$path,'assets/editor-catalog.model.json');
});
test('catalog packaging retains hierarchical identities and existing influence defaults',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'bw-ingame-catalog-'));
 t.after(()=>fs.rm(root,{recursive:true,force:true}));
 await fs.mkdir(path.join(root,'worlds'),{recursive:true});
 await fs.mkdir(path.join(root,'assets/roblox/Trees'),{recursive:true});
 await fs.mkdir(path.join(root,'assets/roblox/Decorations'),{recursive:true});
 // Discovery uses file identities, not conversion; native geometry is tested in Luau.
 await fs.writeFile(path.join(root,'assets/roblox/Trees/Oak.rbxmx'),'native-export-fixture');
 await fs.writeFile(path.join(root,'assets/roblox/Decorations/Oak.rbxmx'),'native-export-fixture');
 await fs.writeFile(path.join(root,'worlds/roblox-assets.json'),JSON.stringify({oak:{model:'Trees/Oak',source:'Trees/Oak',displayName:'Oak',size:[4,12,4],solid:true,destructible:true,collider:{widthFraction:.3,depthFraction:.3,heightFraction:.5}},decoration:{model:'Decorations/Oak',source:'Decorations/Oak',size:[4,12,4],solid:false,destructible:false,collider:{widthFraction:1,depthFraction:1,heightFraction:1}}}));
 const items=await buildEditorCatalog(root);
 const oak=items.find(i=>i.model==='Trees/Oak'),other=items.find(i=>i.model==='Decorations/Oak');
 assert.notEqual(oak.id,other.id);assert.equal(oak.solid,true);assert.equal(oak.destructible,true);assert.equal(other.solid,false);
 const doc=fresh('ingame_export','In-game export');
 doc.objects=[{id:'object_1',type:oak.id,asset:oak.model,bounds:[4,12,4],position:[12.25,0,-40],rotation:[0,37,0],scale:1.25,solid:true,destructible:true,hp:225},{id:'object_2',type:other.id,asset:other.model,bounds:[4,12,4],position:[-20.5,0,-40],rotation:[0,12,0],scale:.75,solid:false,destructible:false,hp:100}];
 const result=compileDocument(JSON.parse(JSON.stringify(doc)),items);
 assert.deepEqual(result.document.objects.map(o=>o.asset),['Trees/Oak','Decorations/Oak']);
 assert.equal(result.manifest.objects[0].influences.physical.hp,225);
 assert.equal(result.manifest.objects[0].influences.movement.collision,'solid');
 assert.equal(result.manifest.objects[1].influences.movement.collision,'none');
});
