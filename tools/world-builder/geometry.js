'use strict';
// Same lowest-visual-point / Rx*Ry*Rz bounding contract as ModelPlacement.
const {trs}=require('../world/transform');
function box(object,fractions) {
 const m=trs([0,0,0],object.rotation,1),size=object.bounds.map((n,i)=>n*object.scale*(object.stretch?.[i]??1));
 const right=m.slice(0,3),up=m.slice(4,7),back=m.slice(8,11);
 const extent=size.map((_,row)=>(Math.abs(right[row])*size[0]+Math.abs(up[row])*size[1]+Math.abs(back[row])*size[2])/2);
 const center=[object.position[0],object.position[1]+extent[1],object.position[2]];
 if(fractions){for(let i=0;i<3;i++)center[i]+=up[i]*size[1]*(fractions[1]-1)/2;for(let i=0;i<3;i++)size[i]*=fractions[i];}
 const extents=size.map((_,row)=>(Math.abs(right[row])*size[0]+Math.abs(up[row])*size[1]+Math.abs(back[row])*size[2])/2);
 const upright=Math.abs(up[1]-1)<1e-6,a=object.rotation[1]*Math.PI/180;
 return {center,size,right,up,back,x:center[0],z:center[2],hx:upright?size[0]/2:extents[0],hz:upright?size[2]/2:extents[2],c:upright?Math.cos(a):1,s:upright?Math.sin(a):0,bottom:center[1]-extents[1],top:center[1]+extents[1],extents};
}
function cells(base,profile){
 if(!profile)return [base];
 return profile.map(cell=>{
  const {right,up,back}=base,axes=[right,up,back];
  const center=base.center.map((n,i)=>n+axes.reduce((sum,axis,j)=>sum+axis[i]*base.size[j]*cell.center[j],0));
  const size=base.size.map((n,i)=>n*cell.size[i]);
  const extents=size.map((_,i)=>axes.reduce((sum,axis,j)=>sum+Math.abs(axis[i])*size[j]/2,0));
  const upright=Math.abs(up[1]-1)<1e-6;
  return {...base,center,size,extents,x:center[0],z:center[2],hx:upright?size[0]/2:extents[0],hz:upright?size[2]/2:extents[2],bottom:center[1]-extents[1],top:center[1]+extents[1]};
 });
}
function faces(base,profile,bases,walls=[]){
 return [...profile,...walls].map((face,index)=>{
  const points=face.flatMap(v=>[v,[v[0],index>=profile.length?v[1]:(bases?.[index]??-.5),v[2]]]).map(v=>base.center.map((n,i)=>n+base.right[i]*base.size[0]*v[0]+base.up[i]*base.size[1]*v[1]+base.back[i]*base.size[2]*v[2]));
  const low=[0,1,2].map(i=>Math.min(...points.map(p=>p[i]))),high=[0,1,2].map(i=>Math.max(...points.map(p=>p[i])));
  return {x:(low[0]+high[0])/2,z:(low[2]+high[2])/2,hx:(high[0]-low[0])/2,hz:(high[2]-low[2])/2,c:1,s:0,bottom:low[1],top:high[1]};
 });
}
function spawnHits(p,b,radius=6){if(b.bottom>=p[1]+6||b.top<=p[1])return false;const dx=p[0]-b.x,dz=p[2]-b.z;return Math.abs(b.c*dx-b.s*dz)<b.hx+radius&&Math.abs(b.s*dx+b.c*dz)<b.hz+radius;}
module.exports={box,cells,faces,spawnHits};
