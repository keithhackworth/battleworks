'use strict';
const test=require('node:test');const assert=require('node:assert/strict');
const fs=require('node:fs/promises');const path=require('node:path');const os=require('node:os');
const {spawnSync}=require('node:child_process');const {createHash}=require('node:crypto');
const {nativeExports}=require('../tools/native-assets');
const {catalogData}=require('../tools/world-builder/catalog');
const {buildEditorCatalog}=require('../tools/build-editor-catalog');
const {validateAssets}=require('../tools/roblox-assets');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const model=(name,ref,child='')=>`<Item class="Model" referent="${ref}"><Properties><string name="Name">${name}</string></Properties>${child||`<Item class="MeshPart" referent="${ref}P"><Properties><string name="Name">Mesh</string><Content name="MeshId"><url>rbxassetid://123456</url></Content></Properties></Item>`}</Item>`;
const folder=(name,ref,child)=>`<Item class="Folder" referent="${ref}"><Properties><string name="Name">${name}</string></Properties>${child}</Item>`;
const XML='<roblox version="4">'+folder('Exported Asset Library','ROOT',folder('Trees','T',model('Oak','O',model('PrimitiveGroup','P')))+folder('Decorations','D',model('Oak','DO'))+folder('Buildings','B',model('House1','H1')+model('House2','H2')))+'</roblox>';
function rojo(args){const r=spawnSync('rojo',args,{encoding:'utf8',maxBuffer:32*1024*1024});assert.ifError(r.error);assert.equal(r.status,0,r.stderr);return r.stdout;}
async function fixture(t,extension='rbxm',xml=XML){
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'bw-bulk-assets-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 await fs.mkdir(path.join(root,'assets/roblox'),{recursive:true});await fs.mkdir(path.join(root,'worlds'));
 await fs.writeFile(path.join(root,'worlds/roblox-assets.json'),'{}');
 const input=path.join(root,'source.rbxmx');await fs.writeFile(input,xml);
 const bundle=path.join(root,'assets/roblox/assets.'+extension);
 if(extension==='rbxm'){
  const project=path.join(root,'fixture.project.json');await fs.writeFile(project,JSON.stringify({name:'NativeBinaryFixture',tree:{$path:input}}));
  // A native model fixture, never a game/place build. Rojo serializes RBXM.
  rojo(['build',project,'-o',bundle]);assert.ok((await fs.readFile(bundle)).subarray(0,8).equals(Buffer.from('<roblox!')));
 }else await fs.copyFile(input,bundle);
 return {root,bundle};
}
for(const extension of ['rbxm','rbxmx'])test(`${extension} Folder bundles expose independent hierarchical Models without altering native bytes`,async t=>{
 const {root,bundle}=await fixture(t,extension);const before=hash(await fs.readFile(bundle));
 const exports=await nativeExports(path.join(root,'assets/roblox'));
 assert.deepEqual(exports.map(e=>e.path),['Buildings/House1','Buildings/House2','Decorations/Oak','Trees/Oak']);
 assert.ok(exports.every(e=>e.nativePath==='assets/'+e.path&&e.file===bundle));
 const items=await buildEditorCatalog(root);const external=items.filter(i=>!i.model.startsWith('Builtin/'));
 assert.equal(external.length,4);assert.equal(new Set(external.map(i=>i.id)).size,4);
 assert.equal(external.filter(i=>i.name==='Oak').length,2);
 assert.ok(!items.some(i=>i.model==='assets'||i.name==='PrimitiveGroup'));
 const index=JSON.parse(JSON.parse(await fs.readFile(path.join(root,'assets/asset-index.model.json'),'utf8')).Properties.Value);
 assert.equal(index.paths['Trees/Oak'],'assets/Trees/Oak');
 assert.equal(hash(await fs.readFile(bundle)),before,'catalog inspection does not rewrite geometry, mesh IDs, names or references');
 // Prove the actual Rojo mount matches every generated runtime path.
 const projectFile=path.join(root,'default.project.json');
 await fs.writeFile(projectFile,JSON.stringify({name:'BundleMount',tree:{$className:'DataModel',ServerStorage:{$className:'ServerStorage',BattleWorksAssets:{$className:'Folder',$path:'assets/roblox',$ignoreUnknownInstances:true,__BattleWorksAssetIndex:{$path:'assets/asset-index.model.json'}}}}}));
 const map=JSON.parse(rojo(['sourcemap',projectFile,'--include-non-scripts']));
 let library=map.children.find(n=>n.name==='ServerStorage').children.find(n=>n.name==='BattleWorksAssets');
 for(const physical of Object.values(index.paths)){
  let node=library;for(const segment of physical.split('/'))node=node.children.find(n=>n.name===segment);
  assert.equal(node.className,'Model');
 }
 const validation=await validateAssets({projectFile});assert.equal(validation.models,4);assert.equal(validation.files.length,1);
});
test('existing individual exports coexist with bundles and retain their saved-world identities',async t=>{
 const {root,bundle}=await fixture(t);
 await fs.mkdir(path.join(root,'assets/roblox/Props'));
 await fs.writeFile(path.join(root,'assets/roblox/Props/Crate.rbxmx'),'<roblox version="4">'+model('OriginalName','C')+'</roblox>');
 await fs.writeFile(path.join(root,'worlds/roblox-assets.json'),JSON.stringify({oldHouse:{model:'House1',source:'GLBs/house.glb',solid:true,destructible:true,collider:{widthFraction:.8,depthFraction:1,heightFraction:1}},oak:{model:'Trees/Oak',source:'oak.glb'}}));
 const data=await catalogData(root);const old=data.items.find(i=>i.id==='asset.oldHouse');
 assert.equal(old.model,'House1');assert.equal(old.palettePath,'Buildings/House1');assert.equal(old.solid,true);assert.equal(old.collider.widthFraction,.8);
 assert.equal(data.index.paths.House1,'assets/Buildings/House1');assert.equal(data.index.paths['Props/Crate'],'Props/Crate');
 assert.equal(data.items.filter(i=>i.model==='Buildings/House1').length,0,'registered aliases do not duplicate the same geometry in the palette');
 const ids=new Map(data.items.map(i=>[i.model,i.id]));await fs.rename(bundle,path.join(root,'assets/roblox/renamed.rbxm'));
 const next=await catalogData(root);for(const item of next.items)assert.equal(item.id,ids.get(item.model),'renaming the bundle never changes logical IDs');
 assert.equal(next.index.paths['Trees/Oak'],'renamed/Trees/Oak');
});
test('duplicate logical bundle paths and ambiguous legacy registry names fail clearly',async t=>{
 const {root,bundle}=await fixture(t);
 await fs.copyFile(bundle,path.join(root,'assets/roblox/second.rbxm'));
 await assert.rejects(catalogData(root),/Duplicate logical asset path/);
 await fs.rm(path.join(root,'assets/roblox/second.rbxm'));
 await fs.writeFile(path.join(root,'worlds/roblox-assets.json'),JSON.stringify({ambiguous:{model:'Oak'}}));
 await assert.rejects(catalogData(root),/Ambiguous registered asset.*Decorations\/Oak.*Trees\/Oak/);
});
test('duplicate sibling names are rejected instead of choosing arbitrary geometry',async t=>{
 const xml='<roblox version="4">'+folder('Library','R',model('Oak','A')+model('Oak','B'))+'</roblox>';
 const {root}=await fixture(t,'rbxm',xml);
 await assert.rejects(catalogData(root),/duplicate sibling name 'Oak'/);
});
test('bundle and filesystem mount collisions are rejected before metadata is written',async t=>{
 const {root}=await fixture(t);
 await fs.mkdir(path.join(root,'assets/roblox/assets/Trees'),{recursive:true});
 await fs.writeFile(path.join(root,'assets/roblox/assets/Trees/Oak.rbxmx'),'<roblox version="4">'+model('Oak','ALTERNATE')+'</roblox>');
 await assert.rejects(buildEditorCatalog(root),/Duplicate native mount path/);
});
test('corrupt bundles leave previously generated metadata untouched',async t=>{
 const {root,bundle}=await fixture(t);await buildEditorCatalog(root);
 const files=['assets/editor-catalog.model.json','assets/asset-index.model.json'];const before=await Promise.all(files.map(f=>fs.readFile(path.join(root,f),'utf8')));
 await fs.writeFile(bundle,'corrupt binary');await assert.rejects(buildEditorCatalog(root),/rojo sourcemap failed/);
 assert.deepEqual(await Promise.all(files.map(f=>fs.readFile(path.join(root,f),'utf8'))),before);
});
test('reserved bundled built-ins never replace or duplicate generated built-in catalog entries',async t=>{
 const xml='<roblox version="4">'+folder('Library','R',folder('Builtin','B',model('BW_block','BLOCK'))+folder('Trees','T',model('Oak','O')))+'</roblox>';
 const {root}=await fixture(t,'rbxm',xml);const {items,index}=await catalogData(root);
 assert.equal(items.filter(i=>i.model==='Builtin/BW_block').length,1);assert.equal(index.paths['Builtin/BW_block'],undefined);
 assert.equal(items.filter(i=>i.model==='Trees/Oak').length,1);
});
