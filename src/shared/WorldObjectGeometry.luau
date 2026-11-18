-- Oriented native bounding boxes, shared by authoring and server world contacts.
-- Position retains the existing placement contract: lowest visual point, not pivot.
local G={MaxStep=1.5,MinSupportNormal=math.cos(math.rad(45))}
local function dot(a,b)return a.X*b.X+a.Y*b.Y+a.Z*b.Z end
function G.axes(rotation)
 local x,y,z=math.rad(rotation[1]),math.rad(rotation[2]),math.rad(rotation[3])
 local cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
 return Vector3.new(cy*cz,cx*sz+sx*sy*cz,sx*sz-cx*sy*cz),
  Vector3.new(-cy*sz,cx*cz-sx*sy*sz,sx*cz+cx*sy*sz),Vector3.new(sy,-sx*cy,cx*cy)
end
function G.rotation(right,up,back)
 local cy=math.sqrt(back.Y*back.Y+back.Z*back.Z)
 local y=math.atan2(back.X,cy)
 local x=if cy>1e-6 then math.atan2(-back.Y,back.Z) else math.atan2(up.Z,up.Y)
 local z=if cy>1e-6 then math.atan2(-up.X,right.X) else 0
 return {math.deg(x)%360,math.deg(y)%360,math.deg(z)%360}
end
function G.extents(box)
 local r,u,b,s=box.right,box.up,box.back,box.size/2
 return Vector3.new(math.abs(r.X)*s.X+math.abs(u.X)*s.Y+math.abs(b.X)*s.Z,
  math.abs(r.Y)*s.X+math.abs(u.Y)*s.Y+math.abs(b.Y)*s.Z,math.abs(r.Z)*s.X+math.abs(u.Z)*s.Y+math.abs(b.Z)*s.Z)
end
function G.from(position,rotation,bounds,scale,fractions)
 local r,u,b=G.axes(rotation)
 local size=Vector3.new(table.unpack(bounds))*scale
 local box={position=Vector3.new(table.unpack(position)),right=r,up=u,back=b,size=size}
 local e=G.extents(box);box.position+=Vector3.new(0,e.Y,0)
 if fractions then
  box.position+=u*(-size.Y/2+size.Y*fractions[2]/2)
  box.size=Vector3.new(size.X*fractions[1],size.Y*fractions[2],size.Z*fractions[3])
 end
 box.extents=G.extents(box)
 return box
end
function G.fromBox(frame,size)
 local box={position=frame.Position,right=frame.RightVector,up=frame.UpVector,back=frame.LookVector*-1,size=size}
 box.extents=G.extents(box);return box
end
function G.cells(box,cells)
 if not cells then return {box} end
 local out={}
 for _,cell in cells do
  local c,s=cell.center,cell.size
  local b={position=box.position+box.right*(box.size.X*c[1])+box.up*(box.size.Y*c[2])+box.back*(box.size.Z*c[3]),right=box.right,up=box.up,back=box.back,size=Vector3.new(box.size.X*s[1],box.size.Y*s[2],box.size.Z*s[3])}
  b.extents=G.extents(b);table.insert(out,b)
 end
 return out
end
function G.faces(box,faces,bases,walls)
 local out={}
 assert(type(faces)=="table" and #faces>0 and #faces<=512,"Invalid terrain face profile")
 local entries={}
 if bases then assert(#bases==#faces,"Invalid face base count")end
 for i,face in faces do table.insert(entries,{face=face,base=if bases then bases[i] else -.5})end
 if walls then assert(#walls<=2048,"Invalid wall count");for _,face in walls do table.insert(entries,{face=face,wall=true})end end
 for _,entry in entries do
  local face=entry.face
  assert(type(face)=="table" and #face==3,"Invalid terrain triangle")
  local vertices,points={},{}
  for _,v in face do
   assert(type(v)=="table" and #v==3,"Invalid terrain vertex")
   for _,n in v do assert(type(n)=="number" and n==n and math.abs(n)<=.501,"Invalid terrain coordinate")end
   local p=box.position+box.right*(v[1]*box.size.X)+box.up*(v[2]*box.size.Y)+box.back*(v[3]*box.size.Z)
   table.insert(vertices,p);table.insert(points,p)
   local base=if entry.wall then v[2] else entry.base
   assert(type(base)=="number" and base==base and base>=-.501 and base<=v[2]+.001,"Invalid face underside")
   table.insert(points,p-box.up*((v[2]-base)*box.size.Y))
  end
  local a,b=vertices[2]-vertices[1],vertices[3]-vertices[1]
  local normal=Vector3.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X)
  -- Native Vector3 quantization can collapse microscopic details after a
  -- small scale/large translation. Skip those zero-area faces, not the asset.
  if normal.Magnitude>1e-12 then
  local low,high={math.huge,math.huge,math.huge},{-math.huge,-math.huge,-math.huge}
  for _,p in points do for i,n in {p.X,p.Y,p.Z}do low[i]=math.min(low[i],n);high[i]=math.max(high[i],n)end end
  local center=Vector3.new((low[1]+high[1])/2,(low[2]+high[2])/2,(low[3]+high[3])/2)
  table.insert(out,{position=center,extents=Vector3.new(high[1]-low[1],high[2]-low[2],high[3]-low[3])/2,up=normal/normal.Magnitude,vertices=vertices,points=points,wall=entry.wall})
  end
 end
 return out
end
function G.topVertices(box)
 if box.vertices then return box.vertices end
 local top=box.position+box.up*(box.size.Y/2);local vertices={}
 for _,corner in {{-1,-1},{1,-1},{1,1},{-1,1}}do table.insert(vertices,top+box.right*(corner[1]*box.size.X/2)+box.back*(corner[2]*box.size.Z/2))end
 return vertices
end
function G.planar(box,yaw)
 if box.vertices then local e=box.extents;return {x=box.position.X,z=box.position.Z,y=box.position.Y,hx=e.X,hz=e.Z,c=1,s=0,yaw=0,bottom=box.position.Y-e.Y,top=box.position.Y+e.Y}end
 local upright=math.abs(box.up.Y-1)<1e-6
 yaw=if upright then math.atan2(-box.right.Z,box.right.X) else 0
 local extents=G.extents(box)
 return {x=box.position.X,z=box.position.Z,y=box.position.Y,
  hx=if upright then box.size.X/2 else extents.X,hz=if upright then box.size.Z/2 else extents.Z,
  c=if upright then math.cos(yaw) else 1,s=if upright then math.sin(yaw) else 0,
  yaw=yaw,bottom=box.position.Y-extents.Y,top=box.position.Y+extents.Y}
end
function G.spawnBlocked(box,yaw,spawn,radius)
 local p=G.planar(box,yaw);radius=radius or 6
 if p.bottom>=spawn[2]+6 or p.top<=spawn[2] then return false end
 local x,z=spawn[1]-p.x,spawn[3]-p.z
 return math.abs(p.c*x-p.s*z)<p.hx+radius and math.abs(p.s*x+p.c*z)<p.hz+radius
end
function G.planeHeight(box,x,z)
 -- Native CFrame components have float precision; an authored 45-degree face
 -- must not switch between walkable and non-walkable at the exact limit.
 if box.up.Y<G.MinSupportNormal-1e-6 then return nil end
 local top=if box.vertices then box.vertices[1] else box.position+box.up*(box.size.Y/2)
 return top.Y-(box.up.X*(x-top.X)+box.up.Z*(z-top.Z))/box.up.Y
end
local function topPoint(box,x,z,clamp)
 local y=G.planeHeight(box,x,z)
 if not y then return nil end
 if box.vertices then
  local sign,inside=0,true
  local closest,distance=nil,math.huge
  for i,a in box.vertices do
   local b=box.vertices[i%#box.vertices+1];local dx,dz=b.X-a.X,b.Z-a.Z
   local cross=dx*(z-a.Z)-dz*(x-a.X)
   if math.abs(cross)>1e-7 then local nextSign=if cross>0 then 1 else -1;if sign~=0 and sign~=nextSign then inside=false end;sign=nextSign end
   local denominator=dx*dx+dz*dz
   local t=if denominator>1e-12 then math.clamp(((x-a.X)*dx+(z-a.Z)*dz)/denominator,0,1) else 0
   local px,pz=a.X+t*dx,a.Z+t*dz;local d=(px-x)^2+(pz-z)^2
   if d<distance then distance=d;closest=Vector3.new(px,G.planeHeight(box,px,pz),pz)end
  end
  return if inside then Vector3.new(x,y,z) elseif clamp then closest else nil
 end
 local top=box.position+box.up*(box.size.Y/2)
 local delta=Vector3.new(x,y,z)-top
 local lx,lz=dot(delta,box.right),dot(delta,box.back)
 if not clamp and (math.abs(lx)>box.size.X/2+.001 or math.abs(lz)>box.size.Z/2+.001) then return nil end
 return top+box.right*math.clamp(lx,-box.size.X/2,box.size.X/2)+box.back*math.clamp(lz,-box.size.Z/2,box.size.Z/2)
end
function G.support(box,x,z,maxHeight)
 local e=box.extents
 if e and (math.abs(x-box.position.X)>e.X+.001 or math.abs(z-box.position.Z)>e.Z+.001 or box.position.Y-e.Y>maxHeight) then return nil end
 local point=topPoint(box,x,z,false)
 return if point and point.Y<=maxHeight+.001 then point.Y else nil
end
function G.canTraverse(box,position,radius,state)
 local e=box.extents;radius=radius or 0
 if e and (math.abs(position.X-box.position.X)>e.X+radius or math.abs(position.Z-box.position.Z)>e.Z+radius) then return false end
 -- A short bevel/riser obeys the same step allowance as a short block. It
 -- still supplies no walkable plane; the adjoining top must support the tank.
 if box.vertices and box.up.Y<G.MinSupportNormal-1e-6 then return box.position.Y+e.Y<=position.Y+G.MaxStep+.001 end
 local point=topPoint(box,position.X,position.Z,true)
 local support=position.Y
 if point and state and state.surface=="Structure" and (state.lift or 0)<.001 then
  -- The nose reaches a platform before the chassis center. Compare that edge
  -- with the current supported incline, rather than treating the pitched hull
  -- as a flat body whose entire bottom is at center height.
  local dx,dz=point.X-position.X,point.Z-position.Z
  local s,c=math.sin(state.yaw),math.cos(state.yaw)
  local pitch=math.clamp(state.groundPitch or 0,-math.pi/4,math.pi/4)
  local roll=math.clamp(state.groundRoll or 0,-math.pi/4,math.pi/4)
  support+=(-s*dx-c*dz)*math.tan(pitch)+(c*dx-s*dz)*math.tan(roll)
 end
 return point and point.Y<=support+G.MaxStep+.001
end
return G
