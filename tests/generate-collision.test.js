'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
const {readGlb,writeGlb,visualGlb,extractFaces,extractPairedFaces}=require('../tools/glb-collision');
const {generateCollision,processFiles}=require('../tools/generate-collision');
const {importGlb,importDirectory}=require('../tools/import-glb');
const {generateCollisions,alignProfile}=require('../tools/bulk-collision');

test('native axis alignment reflects points while preserving surface winding and heights',()=>{
 const triangle=[[-.3,.1,-.4],[-.3,.1,.2],[.4,.1,-.4]];
 const profile={sourceSize:[3,1,4],faces:[triangle],walls:[triangle],bases:[-.2],
  snap:{faces:[triangle],segments:[[triangle[0],triangle[1]]]}};
 const aligned=alignProfile(profile,[-3,2,-1]);
 const expected=[[.4,.1,.3],[.4,.1,-.4],[-.2,.1,.3]];
 assert.deepEqual(aligned.sourceSize,[4,1,3]);
 assert.deepEqual(aligned.faces,[expected]);
 assert.deepEqual(aligned.walls,[expected]);
 assert.deepEqual(aligned.bases,[-.2]);
 assert.deepEqual(aligned.snap,{faces:[expected],segments:[[expected[0],expected[2]]]});
 assert.deepEqual(profile.faces,[triangle]);
 assert.throws(()=>alignProfile(profile,[1,3,2]),/Invalid native collision axes/);
});

function glb(meshes, setup=()=>{}){
 const buffers=[];
 let offset=0;
 const json={asset:{version:'2.0'},buffers:[{byteLength:0}],bufferViews:[],accessors:[],meshes:[],nodes:[],scenes:[{nodes:[]}],scene:0,materials:[{name:'original finish'}]};
 for(const [index,triangles] of meshes.entries()){
  const data=Buffer.alloc(triangles.length*36);
  triangles.flat(2).forEach((n,i)=>data.writeFloatLE(n,i*4));
  buffers.push(data);
  const view=json.bufferViews.push({buffer:0,byteOffset:offset,byteLength:data.length})-1;
  offset+=data.length;
  const positions=json.accessors.push({bufferView:view,type:'VEC3',componentType:5126,count:triangles.length*3})-1;
  json.meshes.push({primitives:[{attributes:{POSITION:positions},material:0}]});
  json.nodes.push({name:`Visible_${index}`,mesh:index});json.scenes[0].nodes.push(index);
 }
 json.buffers[0].byteLength=offset;setup(json);
 return writeGlb(json,[{kind:0x4e4f534a},{kind:0x004e4942}],Buffer.concat(buffers));
}
const quad=(a,b,c,d)=>[[a,b,c],[a,c,d]];
function box(x0,x1,y0,y1,z0,z1){
 const a=[x0,y1,z0],b=[x0,y1,z1],c=[x1,y1,z1],d=[x1,y1,z0];
 const e=[x0,y0,z0],f=[x0,y0,z1],g=[x1,y0,z1],h=[x1,y0,z0];
 return [...quad(a,b,c,d),...quad(e,h,g,f),...quad(e,f,b,a),...quad(h,d,c,g),...quad(e,a,d,h),...quad(f,g,c,b)];
}
function ranges(profile,face,axis){
 return face.map(p=>p[axis]*profile.sourceSize[axis]);
}
function floorAt(profile,x,z){
 return profile.faces.flatMap((face,i)=>{
  const [a,b,c]=face.map(p=>p.map((n,j)=>n*profile.sourceSize[j]));
  const u=[b[0]-a[0],b[2]-a[2]],v=[c[0]-a[0],c[2]-a[2]];
  const det=u[0]*v[1]-u[1]*v[0],px=x-a[0],pz=z-a[2];
  const s=(px*v[1]-pz*v[0])/det,t=(u[0]*pz-u[1]*px)/det;
  if(s < -1e-7||t < -1e-7||s+t > 1+1e-7)return [];
  return [{y:a[1]+s*(b[1]-a[1])+t*(c[1]-a[1]),base:profile.bases[i]*profile.sourceSize[1]}];
 });
}
test('exact cube retains support, sidewalls, appearance and repeatable GLB output',()=>{
 const original=glb([box(-1,1,0,1,-1,1)]);
 const result=generateCollision(original,{mode:'exact'});
 assert.equal(result.report.visualTriangles,12);
 assert.equal(result.report.collisionTriangles,12);
 assert.deepEqual(result.profile.sourceSize,[2,1,2]);
 assert.equal(result.profile.faces.length,2);
 assert.equal(result.profile.walls.length,8);
 const originalData=readGlb(original),filtered=readGlb(visualGlb(result.bytes));
 assert.deepEqual(filtered.json.nodes[0],originalData.json.nodes[0]);
 assert.deepEqual(filtered.json.meshes,originalData.json.meshes);
 assert.deepEqual(filtered.json.materials,originalData.json.materials);
 assert.deepEqual(filtered.bin.subarray(0,originalData.bin.length),originalData.bin);
 assert.deepEqual(generateCollision(result.bytes,{mode:'exact','replace-collision':true}).bytes,result.bytes);
});
test('simplification removes a coplanar interior fan without changing the rim or separating a ramp',()=>{
 const rim=[[-1,0,-1],[-1,0,1],[1,1,1],[1,1,-1]],center=[0,.5,0];
 const deck=rim.map((p,i)=>[center,p,rim[(i+1)%4]]);
 const bytes=glb([deck]);
 const exact=generateCollision(bytes,{mode:'exact'}),simplified=generateCollision(bytes);
 assert.equal(exact.profile.faces.length,4);
 assert.equal(simplified.profile.faces.length,2);
 for(const x of [-.9,-.2,.25,.9]){
  const before=floorAt(exact.profile,x,.1),after=floorAt(simplified.profile,x,.1);
  assert.ok(before.length&&after.length&&Math.abs(before[0].y-after[0].y)<1e-6);
 }
 assert.throws(()=>generateCollision(bytes,{'max-triangles':1}),/limit 1/);
});
test('curved incline and banked curve retain connected, distinct driving normals',()=>{
 for(const bank of [0,.28]){
  const triangles=[];
  const sample=(i,edge)=>{
   const angle=i*Math.PI/24,radius=5+edge;
   return [Math.cos(angle)*radius,i*i*.025+edge*bank,Math.sin(angle)*radius];
  };
  for(let i=0;i<8;i++)triangles.push(...quad(sample(i,-1),sample(i+1,-1),sample(i+1,1),sample(i,1)));
  const result=generateCollision(glb([triangles]),{threshold:.000001});
  assert.equal(result.profile.faces.length,16);
  const vertexCounts=new Map();
  for(const face of result.profile.faces)for(const vertex of face){
   const key=vertex.join(',');vertexCounts.set(key,(vertexCounts.get(key)||0)+1);
  }
  assert.equal(vertexCounts.size,18,'adjacent segments share the same vertices');
  assert.equal(new Set(result.profile.faces.map(face=>ranges(result.profile,face,1).join(','))).size,16);
 }
});
test('U-shaped chute, rectangular tunnel and elevated bridge retain open clearance',()=>{
 const base=box(-3,3,0,.4,-4,4),left=box(-3,-2.5,.4,3,-4,4),right=box(2.5,3,.4,3,-4,4);
 const chute=generateCollision(glb([base,left,right])).profile;
 assert.deepEqual([...new Set(floorAt(chute,0,0).map(face=>face.y.toFixed(3)))],['-1.100']);
 assert.ok(chute.walls.length>=16);
 const roof=box(-3,3,3,3.5,-4,4);
 const tunnel=generateCollision(glb([base,left,right,roof])).profile;
 const levels=floorAt(tunnel,0,.2).sort((a,b)=>a.y-b.y);
 assert.ok(levels.length>=2&&levels[0].y<levels.at(-1).base-2,'roof underside leaves usable space above the tunnel floor');
 const bridge=generateCollision(glb([left,right,roof])).profile;
 assert.ok(floorAt(bridge,0,0).every(face=>face.y-face.base<.51),'bridge deck does not fill the space below it');
 assert.equal(floorAt(bridge,0,4.25).length,0);
});
test('nested transforms, mirrors, independent meshes, helpers and authored collisions',()=>{
 const input=glb([box(-1,1,0,1,-1,1),box(0,1,0,1,0,1),box(0,1,0,1,0,1)],json=>{
  json.scenes[0].nodes=[3];
  json.nodes.push({translation:[4,5,6],children:[0,1,2],rotation:[0,Math.SQRT1_2,0,Math.SQRT1_2]});
  json.nodes[0].scale=[-2,3,4];json.nodes[1].name='SNAP_marker';json.nodes[2].name='collision_manual';
 });
 const preserve=generateCollision(input);
 assert.equal(preserve.bytes,input);assert.equal(preserve.report.existing,'preserved');
 const replace=generateCollision(input,{'replace-collision':true});
 assert.equal(replace.report.visualMeshes,1);
 assert.equal(replace.report.collisionMeshes,1);
 assert.equal(replace.report.existing,'replaced');
 replace.profile.sourceSize.forEach((n,i)=>assert.ok(Math.abs(n-[8,3,4][i])<1e-8));
 assert.equal(replace.profile.walls.length,8);
 assert.ok(replace.report.warnings.some(s=>s.includes('SNAP_marker')));
 assert.deepEqual(replace.profile.snap,preserve.profile.snap,'replacing collision preserves the authored snap mesh');
 assert.deepEqual(generateCollision(replace.bytes,{'replace-collision':true}).bytes,replace.bytes);
 assert.throws(()=>generateCollision(glb([box(-1,1,0,1,-1,1)],json=>{json.nodes[0].scale=[1,0,1];})),/singular/);
});
test('SNAP mesh names and line primitives produce editor-only metadata in the visual coordinate frame',async t=>{
 const body=box(-1,1,0,1,-1,1);
 const source=glb([body,[[[-.5,0,0],[0,0,0],[.5,0,0]]]],json=>{
  json.meshes[1].name='SNAP_connector';
  json.meshes[1].primitives[0].mode=3;
  json.nodes[1].translation=[0,.25,0];
 });
 const automatic=generateCollision(source).profile;
 const paired=extractPairedFaces(source,glb([body]));
 const rendered=visualGlb(source);
 assert.equal(readGlb(rendered).json.meshes.length,1);
 assert.equal(readGlb(rendered).json.nodes[1].mesh,undefined);
 for(const profile of [automatic,paired]){
  const {snap,...collision}=profile;
  assert.deepEqual(snap,{faces:[],segments:[[[-.25,-.25,0],[0,-.25,0]],[[0,-.25,0],[.25,-.25,0]]]});
  assert.deepEqual(collision,generateCollision(rendered).profile);
 }
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'bw-snap-catalog-'));
 t.after(()=>fs.rm(root,{recursive:true,force:true}));
 await fs.mkdir(path.join(root,'worlds'));
 await fs.writeFile(path.join(root,'worlds/asset-collision-generation.json'),'{"enabled":true}');
 await fs.writeFile(path.join(root,'connector.glb'),source);
 const item={model:'Kit/Connector',source:'connector.glb'};
 await generateCollisions(root,[item]);
 assert.deepEqual(item.collider.snap,automatic.snap,'catalog regeneration picks up the authored override from the existing GLB');
});
test('batch, dry-run, visual-only importer and runtime catalog validate the generated source',async t=>{
 const root=await fs.mkdtemp(path.join(os.tmpdir(),'bw-auto-collision-'));
 t.after(()=>fs.rm(root,{recursive:true,force:true}));
 const directory=path.join(root,'GLBs/kit'),sub=path.join(directory,'Nested');
 await fs.mkdir(sub,{recursive:true});
 const original=glb([box(-1,1,0,1,-1,1)]);
 const file=path.join(directory,'Ramp.glb');
 await fs.writeFile(file,original);
 await fs.writeFile(path.join(sub,'Corner.glb'),original);
 const output=path.join(root,'out'),log=()=>{};
 const dry=await processFiles(directory,{'dry-run':true},log);
 assert.equal(dry.length,1);
 await assert.rejects(fs.access(dry[0].output),{code:'ENOENT'});
 const batch=await processFiles(directory,{recursive:true,'output-dir':output},log);
 assert.equal(batch.length,2);
 assert.ok(batch.some(item=>item.output.endsWith('Nested/Corner.with-collision.glb')));
 assert.deepEqual(await fs.readFile(file),original);
 const prepared=path.join(root,'visual.glb');
 const profile=await importGlb(root,'Kit/Ramp',file,{'auto-collision':true,'prepare-only':prepared},log);
 assert.ok(profile.explicitCollision);assert.deepEqual(await fs.readFile(prepared),original);
 assert.deepEqual(extractFaces(await fs.readFile(batch[0].output)),profile);
 const seen=await importDirectory(root,directory,{recursive:true,'auto-collision':true,'asset-prefix':'Kit'},log,async(_,asset)=>asset);
 assert.deepEqual(seen,['Kit/Nested/Corner','Kit/Ramp']);
 await fs.mkdir(path.join(root,'worlds'));
 await fs.writeFile(path.join(root,'worlds/asset-collision-generation.json'),'{"enabled":true,"sourceFolders":{"Kit":"GLBs/kit"}}');
 const item={model:'Kit/Ramp',source:path.relative(root,batch.find(item=>item.output.endsWith('/Ramp.with-collision.glb')).output)};
 const report=await generateCollisions(root,[item]);
 assert.equal(report.assets[0].explicitCollision,true);
 assert.deepEqual(item.collider.faces,profile.faces);
 await fs.mkdir(path.join(root,'assets/roblox'),{recursive:true});
 await fs.writeFile(path.join(root,'worlds/roblox-assets.json'),'{}');
 const registered=await importGlb(root,'Kit/Ramp',file,{'auto-collision':true},log,async upload=>{
  assert.deepEqual(upload,original,'Cloud receives the unchanged visual payload');
  return {assetId:'123456',creatorId:'123',creatorType:'User'};
 });
 assert.equal(registered.collider.explicitCollision,true);
 assert.equal(registered.checkNativeProfile,true,'automatic imports are marked for a native orientation check at load');
 assert.deepEqual(registered.resizeAxes,[true,true,true]);
 assert.equal(registered.source,'GLBs/kit/Ramp.with-collision.glb');
 assert.deepEqual(await fs.readFile(file),original,'import does not modify a source already at the canonical path');
});
