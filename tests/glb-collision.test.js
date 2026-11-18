'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
const {extractFaces,loadFaces}=require('../tools/glb-collision');
function fixture(change=()=>{}){
 // Interleaved positions, accessor and bufferView offsets, unsigned indices.
 const positions=[[0,1,0],[0,1,1],[1,1,0],[0,0,0]];
 const bin=Buffer.alloc(88);positions.forEach((p,i)=>p.forEach((n,j)=>bin.writeFloatLE(n,12+i*16+j*4)));
 [0,1,2,0,3,1].forEach((n,i)=>bin.writeUInt16LE(n,76+i*2));
 const json={asset:{version:'2.0'},buffers:[{byteLength:bin.length}],bufferViews:[{buffer:0,byteOffset:8,byteLength:68,byteStride:16},{buffer:0,byteOffset:76,byteLength:12}],accessors:[{bufferView:0,byteOffset:4,componentType:5126,type:'VEC3',count:4},{bufferView:1,componentType:5123,type:'SCALAR',count:6}],meshes:[{primitives:[{attributes:{POSITION:0},indices:1}]}],nodes:[{mesh:0}],scenes:[{nodes:[0]}],scene:0};
 change(json,bin);
 let text=Buffer.from(JSON.stringify(json));text=Buffer.concat([text,Buffer.alloc((4-text.length%4)%4,32)]);
 const header=Buffer.alloc(12),a=Buffer.alloc(8),b=Buffer.alloc(8);header.writeUInt32LE(0x46546c67);header.writeUInt32LE(2,4);header.writeUInt32LE(12+8+text.length+8+bin.length,8);a.writeUInt32LE(text.length);a.writeUInt32LE(0x4e4f534a,4);b.writeUInt32LE(bin.length);b.writeUInt32LE(0x004e4942,4);
 return Buffer.concat([header,a,text,b,bin]);
}
test('GLB face reader honors binary accessor offsets, stride, indices and upward winding',()=>{
 const profile=extractFaces(fixture());assert.deepEqual(profile.sourceSize,[1,1,1]);assert.equal(profile.faces.length,1);
 assert.deepEqual(profile.faces[0],[[-.5,.5,-.5],[-.5,.5,.5],[.5,.5,-.5]]);
});
test('GLB face reader applies hierarchical TRS/quaternion and matrix transforms before fitting',()=>{
 const profile=extractFaces(fixture(j=>{j.nodes=[{translation:[30,12,-20],rotation:[0,Math.sin(Math.PI/4),0,Math.cos(Math.PI/4)],children:[1]},{mesh:0,scale:[2,3,4]}];}));
 profile.sourceSize.forEach((n,i)=>assert.ok(Math.abs(n-[4,3,2][i])<1e-10));
 const matrix=extractFaces(fixture(j=>j.nodes[0].matrix=[2,0,0,0,0,3,0,0,0,0,4,0,30,12,-20,1]));assert.deepEqual(matrix.sourceSize,[2,3,4]);
 const mirrored=extractFaces(fixture(j=>j.nodes[0].scale=[-2,3,4]));assert.equal(mirrored.faces.length,1);assert.deepEqual(mirrored.sourceSize,[2,3,4]);
});
test('unsupported or invalid binary mesh inputs fail instead of generating misleading colliders',()=>{
 for(const change of [j=>j.accessors[0].sparse={},j=>j.buffers[0].uri='external.bin',j=>j.meshes[0].primitives[0].mode=5,j=>j.meshes[0].primitives[0].extensions={KHR_draco_mesh_compression:{}},j=>j.accessors[0].count=100,j=>j.nodes[0].children=[0],(j,b)=>b.writeUInt16LE(100,76)])assert.throws(()=>extractFaces(fixture(change)),/GLB collision profile/);
 assert.throws(()=>extractFaces(Buffer.from('not a GLB')),/header/);
 const truncated=fixture().subarray(0,60);assert.throws(()=>extractFaces(truncated),/header/);
});
test('actual rocks-ramp retains distinct terraces and bounded triangular metadata',async()=>{
 const source=path.resolve(__dirname,'../GLBs/forest/rocks-ramp.glb');const before=await fs.readFile(source);const profile=await loadFaces(source);
 assert.deepEqual(profile.sourceSize,[1,.5,1]);assert.equal(profile.faces.length,107);
 const levels=new Set();let walkable=0;
 for(const [a,b,c] of profile.faces){
  for(const v of [a,b,c])assert.ok(v.every(n=>Math.abs(n)<=.5+1e-8));
  // Undo normalized bounds before measuring slope.
  const u=b.map((n,i)=>(n-a[i])*profile.sourceSize[i]),v=c.map((n,i)=>(n-a[i])*profile.sourceSize[i]);
  const normal=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];
  if(normal[1]/Math.hypot(...normal)>=Math.cos(Math.PI/4)-1e-6)walkable++;
  if(Math.abs(a[1]-b[1])+Math.abs(a[1]-c[1])<1e-6)levels.add(a[1].toFixed(4));
 }
 assert.equal(walkable,51);assert.ok(levels.size>5);assert.deepEqual(await fs.readFile(source),before);
});
test('face profiles reach catalog, authoring compiler and Studio runtime without altering saved object schema',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'bw-terrain-faces-'));t.after(()=>fs.rm(root,{recursive:true,force:true}));
 await fs.mkdir(path.join(root,'assets/roblox'),{recursive:true});await fs.mkdir(path.join(root,'worlds'));await fs.mkdir(path.join(root,'GLBs'));
 await fs.copyFile(path.resolve(__dirname,'../GLBs/forest/rocks-ramp.glb'),path.join(root,'GLBs/ramp.glb'));
 await fs.writeFile(path.join(root,'worlds/roblox-assets.json'),JSON.stringify({ramp:{model:'Forest/rocks-ramp',source:'GLBs/ramp.glb',collider:{widthFraction:1,heightFraction:1,depthFraction:1}}}));
 await fs.writeFile(path.join(root,'worlds/asset-collision-profiles.json'),JSON.stringify({'Forest/rocks-ramp':{fit:'faces',source:'GLBs/ramp.glb'}}));
 const {catalogData,bindingsFor}=require('../tools/world-builder/catalog');const {fresh,compileDocument}=require('../tools/world-builder/document');
 const {items}=await catalogData(root);const item=items.find(i=>i.model==='Forest/rocks-ramp');assert.equal(item.collider.faces.length,107);item.size=[1,.5,1];
 const document=fresh('terrain');document.objects=[{id:'rock',type:item.id,asset:item.model,position:[0,0,-30],rotation:[0,37,0],scale:45,solid:true,destructible:false,hp:100}];
 const {manifest,document:saved}=compileDocument(document,items);assert.equal(saved.objects[0].faces,undefined);assert.equal(saved.objects[0].fit,undefined);assert.equal(saved.objects[0].asset,item.model);
 const dir=path.join(root,'compiled');await fs.mkdir(dir);await fs.writeFile(path.join(dir,'terrain.json'),JSON.stringify(manifest));
 const catalog=await require('../tools/world/catalog').discoverWorlds(dir,bindingsFor(items));const placement=catalog.Children.find(i=>i.Name==='terrain').Children.find(i=>i.Name==='Placement');
 const fields=Object.fromEntries(placement.Children.map(n=>[n.Name,n.Properties.Value]));assert.equal(fields.ColliderFit,'faces');assert.equal(JSON.parse(fields.ColliderFaces).faces.length,107);
});
