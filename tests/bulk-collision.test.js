'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
const {generateCollisions}=require('../tools/bulk-collision');
const {catalogModel,decodeCatalogModel}=require('../tools/catalog-chunks');
const root=path.resolve(__dirname,'..');
test('bulk pass processes fences, buildings and decorations without changing author flags or identities',async t=>{
 const dir=await fs.mkdtemp(path.join(os.tmpdir(),'bw-bulk-collision-'));t.after(()=>fs.rm(dir,{recursive:true,force:true}));
 await fs.mkdir(path.join(dir,'worlds'));await fs.mkdir(path.join(dir,'sources'));
 await fs.copyFile(path.join(root,'GLBs/forest/fence.glb'),path.join(dir,'sources/fence.glb'));
 await fs.copyFile(path.join(root,'GLBs/suburban/building-type-a.glb'),path.join(dir,'sources/house.glb'));
 await fs.writeFile(path.join(dir,'worlds/asset-collision-generation.json'),JSON.stringify({enabled:true,sourceFolders:{Props:'sources'}}));
 const items=[{id:'old_fence',model:'Props/fence',solid:true,destructible:true,hp:125,defaultScale:45,packaged:true,collider:{widthFraction:.2,heightFraction:.2,depthFraction:.2}},{id:'house',model:'Props/house',solid:false,destructible:false,hp:100,packaged:true},{id:'missing',model:'Props/missing',packaged:true}];
 const identities=items.map(({collider,...rest})=>rest);const before=await fs.readFile(path.join(dir,'sources/fence.glb'));
 const report=await generateCollisions(dir,items);
 assert.equal(report.summary.processed,3);assert.equal(report.summary.faces,2);assert.equal(report.summary.sampled,1);
 assert.deepEqual(items.map(({collider,...rest})=>rest),identities);assert.equal(items[0].collider.fit,'faces');assert.equal(items[1].collider.fit,'faces');assert.equal(items[2].collider.fit,'mesh');
 assert.equal(items[0].collider.widthFraction,1,'actual geometry replaces old enclosing/trunk fractions');
 assert.ok(items[0].collider.walls.length);assert.ok(items[0].collider.bases.some(y=>y>-.4),'fence rails preserve underside clearance');
 assert.match(report.assets[2].reason,/ENOENT/);assert.deepEqual(await fs.readFile(path.join(dir,'sources/fence.glb')),before);
});
test('real catalog covers every imported model, preserves builtins and reports unsupported inputs explicitly',async()=>{
 const model=JSON.parse(await fs.readFile(path.join(root,'assets/editor-catalog.model.json'),'utf8'));const items=decodeCatalogModel(model);
 const imported=items.filter(i=>i.packaged&&!i.model.startsWith('Builtin/'));assert.equal(imported.length,60);
 assert.equal(imported.filter(i=>i.collider.fit==='faces').length,59);
 assert.equal(imported.filter(i=>i.collider.fit==='mesh').length,1);
 for(const item of items.filter(i=>i.model.startsWith('Builtin/')))assert.equal(item.collider.fit,undefined);
 assert.equal(items.find(i=>i.model==='tree-large').id,'asset.tree_large');
 const report=JSON.parse(await fs.readFile(path.join(root,'assets/collision-report.json'),'utf8'));
 assert.equal(report.assets.find(i=>i.asset==='Forest/character-archer').fit,'mesh');assert.match(report.assets.find(i=>i.asset==='Forest/character-archer').reason,/static uncompressed/);
 assert.equal(items.find(i=>i.model==='Surburban/building-type-t').collider.fit,'faces');
 assert.ok(items.find(i=>i.model==='Forest/bridge').collider.bases.some(y=>y>-.4),'bridge deck is not extruded to ground');
 assert.notDeepEqual(items.find(i=>i.model==='Forest/fence').collider.faces,items.find(i=>i.model==='Surburban/fence').collider.faces,'matching is hierarchical, never ambiguous basename guessing');
 assert.equal(report.summary.unavailable,1,'old missing rope-fence stays explicitly unavailable');
 for(const node of [model,...model.Children])assert.ok(node.Properties.Value.length<=170000,'every Roblox string is bounded');
});
test('catalog chunk packaging round-trips small and large payloads with stable ordered parts',()=>{
 for(const payload of [[{id:'small'}],[{id:'large',value:'é'.repeat(500000)}],[{id:'emoji',value:'😀'.repeat(300000)}]]){
  const model=catalogModel(payload);assert.deepEqual(decodeCatalogModel(model),payload);
  for(const node of [model,...model.Children||[]])assert.ok(node.Properties.Value.length<=170000&&node.Properties.Value.isWellFormed());
 }
 const broken=catalogModel([{x:'x'.repeat(300000)}]);broken.Children.pop();assert.throws(()=>decodeCatalogModel(broken));
});
