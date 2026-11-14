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
function G.planar(box,yaw)
 local upright=math.abs(box.up.Y-1)<1e-6
 local extents=G.extents(box)
 return {x=box.position.X,z=box.position.Z,y=box.position.Y,
  hx=if upright then box.size.X/2 else extents.X,hz=if upright then box.size.Z/2 else extents.Z,
  c=if upright then math.cos(yaw) else 1,s=if upright then math.sin(yaw) else 0,
  yaw=if upright then yaw else 0,bottom=box.position.Y-extents.Y,top=box.position.Y+extents.Y}
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
 local top=box.position+box.up*(box.size.Y/2)
 return top.Y-(box.up.X*(x-top.X)+box.up.Z*(z-top.Z))/box.up.Y
end
local function topPoint(box,x,z,clamp)
 local y=G.planeHeight(box,x,z)
 if not y then return nil end
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
