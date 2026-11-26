#!/usr/bin/env node
'use strict';

const fs=require('node:fs/promises');
const path=require('node:path');
const {createHash}=require('node:crypto');
const {parseArgs}=require('node:util');
const {readGlb,writeGlb,readAccessor,walkNodes,extractFaces,isCollisionNode,isSnapMesh,visualGlb}=require('./glb-collision');

const autoOptions={
 mode:{type:'string'},threshold:{type:'string'},passes:{type:'string'},
 'max-triangles':{type:'string'},'replace-collision':{type:'boolean'},
};
const outputSuffix='.with-collision.glb';
const sub=(a,b)=>a.map((v,i)=>v-b[i]);
const dot=(a,b)=>a.reduce((sum,n,i)=>sum+n*b[i],0);
const cross=([a,b,c],[x,y,z])=>[b*z-c*y,c*x-a*z,a*y-b*x];
const normal=([a,b,c])=>cross(sub(b,a),sub(c,a));
const length=v=>Math.hypot(...v);
const vertex=(m,p)=>[0,1,2].map(i=>m[i]*p[0]+m[4+i]*p[1]+m[8+i]*p[2]+m[12+i]);
const helper=node=>/^(?:SNAP|SOCKET|HELPER|MARKER)(?:[_ .-]|$)/i.test(node.name||'')||
 node.extras?.helper===true||node.extras?.snapPoint===true||node.extras?.nonVisual===true;

function optionsFor(options){
 const mode=options.mode||'simplified';
 if(mode==='convex')throw new Error('Convex decomposition is unnecessary: BattleWorks already builds per-face contact prisms. Use exact or simplified to preserve openings.');
 if(!['exact','simplified'].includes(mode))throw new Error('Mode must be exact or simplified');
 const threshold=Number(options.threshold??.000001),passes=Number(options.passes??8),limit=Number(options['max-triangles']??4096);
 if(!Number.isFinite(threshold)||threshold<0||threshold>.01)throw new Error('Threshold must be 0–0.01 in transformed GLB units');
 if(!Number.isInteger(passes)||passes<1||passes>32)throw new Error('Passes must be an integer from 1 to 32');
 if(!Number.isInteger(limit)||limit<1||limit>100000)throw new Error('Max triangles must be an integer from 1 to 100000');
 return {mode,threshold,passes,limit};
}

function readMesh(source,node,m,label,warnings){
 const det=dot(m.slice(0,3),cross(m.slice(4,7),m.slice(8,11)));
 if(Math.abs(det)<1e-12||Math.abs(m[3])+Math.abs(m[7])+Math.abs(m[11])+Math.abs(m[15]-1)>1e-10)throw new Error(`${label}: singular or non-affine transform`);
 const mesh=source.json.meshes?.[node.mesh];
 if(!mesh?.primitives?.length||node.skin!==undefined||node.weights)throw new Error(`${label}: expected static mesh geometry`);
 const positions=[],world=[],triangles=[],unique=new Map();
 let count=0,degenerate=0;
 for(const p of mesh.primitives){
  if((p.mode??4)!==4||p.targets||p.extensions?.KHR_draco_mesh_compression)throw new Error(`${label}: expected uncompressed static triangle primitives`);
  const local=readAccessor(source,p.attributes?.POSITION,true);
  const keys=local.map(point=>{
   const key=point.join(',');
   if(!unique.has(key)){
    unique.set(key,positions.length);positions.push(point);world.push(vertex(m,point));
   }
   return unique.get(key);
  });
  const indices=p.indices===undefined?keys.map((_,i)=>i):readAccessor(source,p.indices).map(v=>v[0]);
  if(indices.length%3||indices.some(i=>i>=keys.length))throw new Error(`${label}: invalid triangle indices`);
  count+=indices.length/3;
  if(count>100000)throw new Error(`${label}: source exceeds 100000 triangles`);
  for(let i=0;i<indices.length;i+=3){
   const face=[keys[indices[i]],keys[indices[i+1]],keys[indices[i+2]]];
   const n=normal(face.map(j=>world[j]));
   if(!n.every(Number.isFinite))throw new Error(`${label}: nonfinite transformed geometry`);
   if(length(n)<=1e-10){degenerate++;continue;}
   triangles.push(face);
  }
 }
 if(degenerate)warnings.push(`${label}: omitted ${degenerate} degenerate triangles`);
 return {positions,world,triangles,count,det,m};
}

// Remove an interior vertex only if its full fan is flat and its boundary
// is one convex ring. Rim edges, holes, creases and curved faces stay intact.
function flatFan(center,incident,triangles,points,tolerance){
 if(incident.length<4)return null;
 const next=new Map();
 const reference=normal(triangles[incident[0]].map(i=>points[i]));
 const axis=reference.map(v=>v/length(reference));
 for(const index of incident){
  const tri=triangles[index],k=tri.indexOf(center),a=tri[(k+1)%3],b=tri[(k+2)%3];
  if(next.has(a)||Math.abs(dot(sub(points[a],points[center]),axis))>tolerance||
   Math.abs(dot(sub(points[b],points[center]),axis))>tolerance||
   dot(normal(tri.map(i=>points[i])),axis)<=0)return null;
  next.set(a,b);
 }
 const first=next.keys().next().value,ring=[first];
 let at=next.get(first);
 while(at!==first&&at!==undefined&&ring.length<next.size){ring.push(at);at=next.get(at);}
 if(at!==first||ring.length!==next.size)return null;
 let angle=0;
 for(let i=0;i<ring.length;i++){
  const a=points[ring[i]],b=points[ring[(i+1)%ring.length]],c=points[ring[(i+2)%ring.length]];
  if(dot(cross(sub(b,a),sub(c,b)),axis)<-1e-12)return null;
  const u=sub(a,points[center]),v=sub(b,points[center]);
  angle+=Math.atan2(dot(cross(u,v),axis),dot(u,v));
 }
 if(Math.abs(angle-2*Math.PI)>1e-4)return null;
 const replacement=[];
 for(let i=1;i+1<ring.length;i++){
  const triangle=[ring[0],ring[i],ring[i+1]];
  // Keep original triangulation if a replacement would lose a boundary edge.
  if(length(normal(triangle.map(j=>points[j])))<=1e-10)return null;
  replacement.push(triangle);
 }
 return replacement;
}
function simplify(triangles,points,tolerance,passes){
 const seen=new Set();
 let faces=triangles.filter(face=>{
  const i=face.indexOf(Math.min(...face)),key=[face[i],face[(i+1)%3],face[(i+2)%3]].join(',');
  if(seen.has(key))return false;
  seen.add(key);return true;
 });
 for(let pass=0;pass<passes;pass++){
  const adjacency=new Map(),removed=new Set(),added=[];
  for(const [index,face] of faces.entries())for(const v of face){
   if(!adjacency.has(v))adjacency.set(v,[]);
   adjacency.get(v).push(index);
  }
  for(const [center,fan] of adjacency){
   if(fan.some(i=>removed.has(i)))continue;
   const replacement=flatFan(center,fan,faces,points,tolerance);
   if(!replacement)continue;
   for(const i of fan)removed.add(i);
   added.push(...replacement);
  }
  if(!removed.size)break;
  faces=faces.filter((_,i)=>!removed.has(i)).concat(added);
 }
 return faces;
}

function appendGeometry(source,groups,stamp){
 const {json,bin}=source;
 const alignment=Buffer.alloc((4-bin.length%4)%4),buffers=[bin,alignment];
 let offset=bin.length+alignment.length;
 function accessor(bytes,count,type,componentType,bounds={}){
  const view=json.bufferViews.push({buffer:0,byteOffset:offset,byteLength:bytes.length})-1;
  offset+=bytes.length;buffers.push(bytes);
  return json.accessors.push({bufferView:view,count,type,componentType,...bounds})-1;
 }
 const roots=(json.scenes[json.scene??0].nodes??=[]);
 for(const [index,group] of groups.entries()){
  const used=[...new Set(group.triangles.flat())];
  const remap=new Map(used.map((id,i)=>[id,i]));
  const vertices=Buffer.alloc(used.length*12),indices=Buffer.alloc(group.triangles.length*12);
  const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];
  used.forEach((id,i)=>group.positions[id].forEach((n,j)=>{
   vertices.writeFloatLE(n,i*12+j*4);min[j]=Math.min(min[j],n);max[j]=Math.max(max[j],n);
  }));
  group.triangles.forEach((tri,i)=>tri.forEach((id,j)=>indices.writeUInt32LE(remap.get(id),i*12+j*4)));
  const name=`COLLISION_Auto_${String(index+1).padStart(3,'0')}`;
  const pos=accessor(vertices,used.length,'VEC3',5126,{min,max});
  const ind=accessor(indices,group.triangles.length*3,'SCALAR',5125);
  const mesh=json.meshes.push({name,primitives:[{attributes:{POSITION:pos},indices:ind}]})-1;
  roots.push(json.nodes.push({name,mesh,matrix:group.m,extras:{battleWorksAutoCollision:stamp}})-1);
 }
 json.buffers[0].byteLength=offset;
 return writeGlb(json,source.chunks,Buffer.concat(buffers));
}

function generateCollision(bytes,options={}){
 const {mode,threshold,passes,limit}=optionsFor(options);
 const source=readGlb(bytes),warnings=[],groups=[],existing=[],visual=[];
 if(source.json.animations?.length)warnings.push('Collision uses the authored rest pose; GLB animations are ignored');
 let visualMeshes=0,visualTriangles=0;
 walkNodes(source,(node,m,index)=>{
  if(node.mesh===undefined)return;
  const label=node.name||`node ${index}`;
  if(isSnapMesh(source.json,node)){warnings.push(`Excluded helper ${label}`);return;}
  if(isCollisionNode(node.name)){existing.push({node,m,label});return;}
  if(helper(node)){warnings.push(`Excluded helper ${label}`);return;}
  visual.push({node,m,label});
 });
 const preserveAuthored=existing.length>0&&!options['replace-collision'];
 for(const {node,m,label} of visual){
  visualMeshes++;
  if(preserveAuthored){
   for(const p of source.json.meshes?.[node.mesh]?.primitives||[]){
    if((p.mode??4)===4)visualTriangles+=(source.json.accessors?.[p.indices??p.attributes?.POSITION]?.count||0)/3;
    else warnings.push(`${label}: non-triangle primitive excluded from the triangle count`);
   }
   continue;
  }
  const group=readMesh(source,node,m,label,warnings);
  visualTriangles+=group.count;
  if(visualTriangles>100000)throw new Error('Visual geometry exceeds 100000 triangles');
  if(mode==='simplified')group.triangles=simplify(group.triangles,group.world,threshold,passes);
  if(group.triangles.some(tri=>normal(tri.map(i=>group.world[i]))[1]*Math.sign(group.det)>=-1e-10))groups.push(group);
  else warnings.push(`${label}: underside-only or empty mesh is not a usable standalone collider`);
 }
 const generatedTriangles=groups.reduce((sum,g)=>sum+g.triangles.length,0);
 const geometry=group=>[group.m,group.triangles.map(triangle=>triangle.map(i=>group.positions[i]))];
 const stamp=createHash('sha256').update(JSON.stringify([mode,threshold,passes,groups.map(geometry)])).digest('hex');
 const unchanged=existing.length>0&&existing.length===groups.length&&existing.every(({node,m,label},i)=>
  node.extras?.battleWorksAutoCollision===stamp&&JSON.stringify(geometry(readMesh(source,node,m,label,[])))===JSON.stringify(geometry(groups[i])));
 const preserved=preserveAuthored||unchanged;
 let output=bytes,collisionMeshes=groups.length,collisionTriangles=generatedTriangles;
 if(preserved){
  collisionMeshes=existing.length;
  collisionTriangles=0;
  for(const {node,m,label} of existing)collisionTriangles+=readMesh(source,node,m,label,warnings).count;
 }else{
  if(!groups.length)throw new Error('No usable collision geometry found');
  if(generatedTriangles>limit)throw new Error(`Generated ${generatedTriangles} triangles; limit ${limit}. Try simplified mode or use a lower-detail source mesh.`);
  output=appendGeometry(existing.length?readGlb(visualGlb(bytes,{keepSnap:true})):source,groups,stamp);
 }
 let profile;
 try{profile=extractFaces(output);}
 catch(error){throw new Error(`Validation failed for ${collisionTriangles} collision triangles: ${error.message}. Use simpler geometry or authored collision.`,{cause:error});}
 if(JSON.stringify(profile).length>170000)throw new Error('Collision profile exceeds the 170000-character catalog limit');
 if(profile.faces.length+profile.walls.length>350)warnings.push('High runtime contact cost: consider fewer support and wall faces');
 if(collisionTriangles>limit)warnings.push(`Preserved geometry exceeds requested triangle limit (${limit})`);
 return {bytes:output,profile,report:{mode,visualMeshes,visualTriangles,collisionMeshes,collisionTriangles,
  existing:existing.length?(preserved?'preserved':'replaced'):'none',validation:'passed',support:profile.faces.length,walls:profile.walls.length,warnings}};
}
async function glbFiles(input,recursive=false){
 const info=await fs.stat(input);
 if(info.isFile()){
  if(!/\.glb$/i.test(input))throw new Error('Expected a GLB file');
  return [input];
 }
 if(!info.isDirectory())throw new Error('Expected a GLB file or directory');
 const files=[];
 for(const entry of (await fs.readdir(input,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))){
  const full=path.join(input,entry.name);
  if(entry.isDirectory()&&recursive)files.push(...await glbFiles(full,true));
  else if(entry.isFile()&&/\.glb$/i.test(entry.name)&&!/(?:\.with-collision|\.collision)\.glb$/i.test(entry.name))files.push(full);
 }
 return files;
}
function reportText(file,report,output){
 return `${file}: ${report.visualMeshes} visual meshes / ${report.visualTriangles} triangles → ${report.collisionMeshes} collision meshes / ${report.collisionTriangles} triangles (${report.mode}; existing: ${report.existing}). Validation ${report.validation}: ${report.support} support, ${report.walls} walls.${output?' Output: '+output:''}`+
  report.warnings.map(warning=>'\n  Warning: '+warning).join('');
}
async function processFiles(input,options={},log=console.log){
 const files=await glbFiles(input,options.recursive);
 if(!files.length)throw new Error('No GLB files found');
 if(options['in-place']&&options['output-dir'])throw new Error('Choose either --in-place or --output-dir');
 const base=(await fs.stat(input)).isDirectory()?input:path.dirname(input),failed=[],results=[];
 for(const file of files){
  try{
   const original=await fs.readFile(file);
   const result=generateCollision(original,options);
   const destination=options['in-place']?file:options['output-dir']?
    path.join(options['output-dir'],path.relative(base,file).replace(/\.glb$/i,outputSuffix)):
    file.replace(/\.glb$/i,outputSuffix);
   if(!options['dry-run']&&(!options['in-place']||!result.bytes.equals(original))){
    await fs.mkdir(path.dirname(destination),{recursive:true});
    const temporary=`${destination}.${process.pid}.tmp`;
    try{
     await fs.writeFile(temporary,result.bytes);
     await fs.rename(temporary,destination);
    }
    finally{await fs.rm(temporary,{force:true});}
   }
   log(reportText(file,result.report,destination+(options['dry-run']?' (dry run)':'')));
   results.push({...result.report,output:destination});
  }catch(error){failed.push(`${file}: ${error.message}`);}
 }
 if(failed.length)throw new Error(failed.join('\n'));
 return results;
}
if(require.main===module)(async()=>{
 const {positionals,values}=parseArgs({allowPositionals:true,options:{...autoOptions,recursive:{type:'boolean'},'dry-run':{type:'boolean'},'output-dir':{type:'string'},'in-place':{type:'boolean'}}});
 if(positionals.length!==1)throw new Error('Usage: node tools/generate-collision.js SOURCE.glb|DIRECTORY [--mode exact|simplified] [--recursive] [--output-dir DIR | --in-place] [--dry-run] [--replace-collision]');
 await processFiles(positionals[0],values);
})().catch(error=>{console.error(error.message);process.exitCode=1;});
module.exports={generateCollision,glbFiles,reportText,processFiles,autoOptions};
