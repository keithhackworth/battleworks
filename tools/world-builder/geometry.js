'use strict';
// Same lowest-visual-point / Rx*Ry*Rz bounding contract as ModelPlacement.
const {trs}=require('../world/transform');
function box(object,fractions) {
 const m=trs([0,0,0],object.rotation,1),size=object.bounds.map(n=>n*object.scale);
 const right=m.slice(0,3),up=m.slice(4,7),back=m.slice(8,11);
 const extent=size.map((_,row)=>(Math.abs(right[row])*size[0]+Math.abs(up[row])*size[1]+Math.abs(back[row])*size[2])/2);
 const center=[object.position[0],object.position[1]+extent[1],object.position[2]];
 if(fractions){for(let i=0;i<3;i++)center[i]+=up[i]*size[1]*(fractions[1]-1)/2;for(let i=0;i<3;i++)size[i]*=fractions[i];}
 const extents=size.map((_,row)=>(Math.abs(right[row])*size[0]+Math.abs(up[row])*size[1]+Math.abs(back[row])*size[2])/2);
 const upright=Math.abs(up[1]-1)<1e-6,a=object.rotation[1]*Math.PI/180;
 return {x:center[0],z:center[2],hx:upright?size[0]/2:extents[0],hz:upright?size[2]/2:extents[2],c:upright?Math.cos(a):1,s:upright?Math.sin(a):0,bottom:center[1]-extents[1],top:center[1]+extents[1],extents};
}
function spawnHits(p,b,radius=6){if(b.bottom>=p[1]+6||b.top<=p[1])return false;const dx=p[0]-b.x,dz=p[2]-b.z;return Math.abs(b.c*dx-b.s*dz)<b.hx+radius&&Math.abs(b.s*dx+b.c*dz)<b.hz+radius;}
module.exports={box,spawnHits};
