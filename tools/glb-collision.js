'use strict';
// Offline, opt-in terrain collision metadata. Native Roblox render assets stay
// untouched. GLB v2 triangle primitives only; unsupported encodings fail clearly.
const fs=require('node:fs/promises');
const {identity,multiply}=require('./world/transform');
function nodeMatrix(node){
 if(node.matrix)return node.matrix;
 const [x,y,z,w]=node.rotation||[0,0,0,1],s=node.scale||[1,1,1],t=node.translation||[0,0,0];
 return [(1-2*y*y-2*z*z)*s[0],(2*x*y+2*z*w)*s[0],(2*x*z-2*y*w)*s[0],0,(2*x*y-2*z*w)*s[1],(1-2*x*x-2*z*z)*s[1],(2*y*z+2*x*w)*s[1],0,(2*x*z+2*y*w)*s[2],(2*y*z-2*x*w)*s[2],(1-2*x*x-2*y*y)*s[2],0,...t,1];
}
function extractFaces(bytes,options={}){
 const fail=m=>{throw new Error('GLB collision profile: '+m);};
 if(bytes.length<20||bytes.readUInt32LE(0)!==0x46546c67||bytes.readUInt32LE(4)!==2||bytes.readUInt32LE(8)!==bytes.length)fail('invalid GLB v2 header');
 let json,bin;
 for(let offset=12;offset<bytes.length;){
  if(offset+8>bytes.length)fail('truncated chunk');const length=bytes.readUInt32LE(offset),kind=bytes.readUInt32LE(offset+4);offset+=8;
  if(offset+length>bytes.length)fail('truncated chunk payload');
  if(kind===0x4e4f534a)json=JSON.parse(bytes.subarray(offset,offset+length).toString('utf8'));
  if(kind===0x004e4942)bin=bytes.subarray(offset,offset+length);offset+=length;
 }
 if(!json||!bin||json.buffers?.length!==1||json.buffers[0].uri)fail('expected one embedded binary buffer');
 const read=(index,position=false)=>{
  const a=json.accessors?.[index],v=json.bufferViews?.[a?.bufferView];
  if(!a||!v||a.sparse||a.normalized||v.buffer!==0||v.extensions?.EXT_meshopt_compression)fail('unsupported accessor');
  const components=position?3:1;
  if(a.type!==(position?'VEC3':'SCALAR')||(position&&a.componentType!==5126))fail('unsupported position/index type');
  if(!position&&![5121,5123,5125].includes(a.componentType))fail('unsupported index component type');
  const types={5121:[1,'readUInt8'],5123:[2,'readUInt16LE'],5125:[4,'readUInt32LE'],5126:[4,'readFloatLE']};
  const type=types[a.componentType];if(!type)fail('unsupported component type');
  const stride=v.byteStride||type[0]*components,start=(v.byteOffset||0)+(a.byteOffset||0),end=(v.byteOffset||0)+v.byteLength;
  if(!Number.isInteger(a.count)||a.count<0||a.count>1000000||!Number.isInteger(stride)||stride<type[0]*components||!Number.isInteger(start)||start<(v.byteOffset||0))fail('invalid accessor dimensions');
  return Array.from({length:a.count},(_,i)=>Array.from({length:components},(_,c)=>{
   const at=start+i*stride+c*type[0];if(at<0||at+type[0]>end||at+type[0]>bin.length)fail('accessor outside buffer');
   const n=bin[type[1]](at);if(!Number.isFinite(n))fail('nonfinite vertex');return n;
  }));
 };
 const triangles=[],downward=[],walls=[],all=[];let budget=0;
 const visit=(index,parent,ancestors)=>{
  if(ancestors.has(index)||!json.nodes?.[index])fail('invalid/cyclic node hierarchy');
  const node=json.nodes[index],m=multiply(parent,nodeMatrix(node));const next=new Set(ancestors);next.add(index);
  if(!m.every(Number.isFinite))fail('invalid node transform');
  const determinant=m[0]*(m[5]*m[10]-m[9]*m[6])-m[4]*(m[1]*m[10]-m[9]*m[2])+m[8]*(m[1]*m[6]-m[5]*m[2]);
  if(node.mesh!==undefined){
   const mesh=json.meshes?.[node.mesh];if(!mesh)fail('missing mesh');
   for(const primitive of mesh.primitives){
    if((primitive.mode??4)!==4||primitive.extensions?.KHR_draco_mesh_compression||primitive.targets||node.skin!==undefined)fail('only static uncompressed triangle primitives are supported');
    const positions=read(primitive.attributes?.POSITION,true).map(p=>[0,1,2].map(i=>m[i]*p[0]+m[4+i]*p[1]+m[8+i]*p[2]+m[12+i]));for(const p of positions)all.push(p);
    const indices=primitive.indices===undefined?positions.map((_,i)=>i):read(primitive.indices).map(v=>v[0]);
    if(indices.length%3||indices.some(i=>!Number.isInteger(i)||i<0||i>=positions.length))fail('invalid triangle indices');
    for(let i=0;i<indices.length;i+=3){
     if(++budget>100000)fail('triangle budget exceeded');
     const tri=indices.slice(i,i+3).map(i=>positions[i]);if(determinant<0)[tri[1],tri[2]]=[tri[2],tri[1]];
     const [a,b,c]=tri;
     const normalY=(b[2]-a[2])*(c[0]-a[0])-(b[0]-a[0])*(c[2]-a[2]);
     // Terrain-only columns beneath upward faces; vertical sides are formed
     // by those prisms. Never use this profile for bridges or overhangs.
     if(normalY>1e-10)triangles.push(tri);
     else if(normalY< -1e-10)downward.push(tri);
     else if(options.preserveClearance){
      const ux=b[0]-a[0],uy=b[1]-a[1],uz=b[2]-a[2],vx=c[0]-a[0],vy=c[1]-a[1],vz=c[2]-a[2];
      if(Math.hypot(uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx)>1e-10)walls.push(tri);
     }
    }
   }
  }
  for(const child of node.children||[])visit(child,m,next);
 };
 const roots=json.scenes?.[json.scene??0]?.nodes;if(!roots)fail('missing scene');for(const root of roots)visit(root,identity(),new Set());
 if(!triangles.length||triangles.length>512)fail('expected 1–512 upward faces');
 const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];for(const p of all)for(let i=0;i<3;i++){min[i]=Math.min(min[i],p[i]);max[i]=Math.max(max[i],p[i]);}
 const size=max.map((v,i)=>v-min[i]);if(size.some(n=>n<=1e-8))fail('mesh has no volume');
 const normalized=t=>{
  const raw=t.map(v=>v.map((n,i)=>(n-(min[i]+max[i])/2)/size[i]));
  if(!options.preserveClearance)return raw;
  const rounded=raw.map(v=>v.map(n=>Math.round(n*1e6)/1e6||0));
  const [a,b,c]=rounded,u=b.map((n,i)=>n-a[i]),v=c.map((n,i)=>n-a[i]);
  return Math.hypot(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])>1e-14?rounded:raw;
 };
 const profile={sourceSize:size,faces:triangles.map(normalized)};
 if(options.preserveClearance){
  if(walls.length>2048)fail('vertical face budget exceeded');
  profile.walls=walls.map(normalized);
  profile.bases=triangles.map(triangle=>{
   let bottom=-Infinity;
   const center=[0,1,2].map(i=>triangle.reduce((s,v)=>s+v[i],0)/3);
   const samples=[center,...triangle.map(v=>v.map((n,i)=>n*.99+center[i]*.01))];
   for(const [x,y,z] of samples){
    let nearest=-Infinity;
    for(const [a,b,c] of downward){
     const det=(b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0]);
     const u=((x-a[0])*(c[2]-a[2])-(z-a[2])*(c[0]-a[0]))/det;
     const v=((b[0]-a[0])*(z-a[2])-(b[2]-a[2])*(x-a[0]))/det;
     if(u< -1e-6||v< -1e-6||u+v>1+1e-6)continue;
     const h=a[1]+u*(b[1]-a[1])+v*(c[1]-a[1]);
     if(h<y-1e-8)nearest=Math.max(nearest,h);
    }
    bottom=Math.max(bottom,nearest);
   }
   // Open surfaces remain shells; do not manufacture a column to the ground.
   const low=Math.min(...triangle.map(v=>v[1]));bottom=Number.isFinite(bottom)?Math.min(bottom,low):low;
   return Math.round((bottom-(min[1]+max[1])/2)/size[1]*1e6)/1e6||0;
  });
 }
 return profile;
}
async function loadFaces(filename,options){return extractFaces(await fs.readFile(filename),options);}
module.exports={extractFaces,loadFaces};
