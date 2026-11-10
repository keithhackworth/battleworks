-- Deterministic planar rigid contacts for the existing scripted simulation.
-- Records are generic body+box geometry; no tank names, Instances or tasks.
local Motion=require(script.Parent.VehicleMotion)
local C={Skin=0.0001,Iterations=10,MaxEvents=12,MaxSubsteps=16,Friction=0.15}
local function dot(x,z,a,b) return x*a+z*b end
local function axes(r) local c,s=math.cos(r.state.yaw),math.sin(r.state.yaw); return c,-s,s,c end
local function extent(r,x,z)
 local ax,az,bx,bz=axes(r)
 return math.abs(dot(ax,az,x,z))*r.halfX+math.abs(dot(bx,bz,x,z))*r.halfZ
end
local function vertical(a,b)
 local ay=a.state.position.Y; local by=b.state.position.Y
 return ay+a.top>by+b.bottom+C.Skin and by+b.top>ay+a.bottom+C.Skin
end
local function separating(a,b,margin)
 if b.plane then
  local p=b.plane; local gap=dot(a.state.position.X,a.state.position.Z,p.nx,p.nz)-p.offset-extent(a,p.nx,p.nz)
  if gap>C.Skin+(margin or 0) then return nil end
  return p.nx,p.nz,math.max(0,-gap),math.max(0,gap)
 end
 if not vertical(a,b) then return nil end
 local radius=a.halfX+a.halfZ+b.halfX+b.halfZ+(margin or 0)+C.Skin
 if math.abs(a.state.position.X-b.state.position.X)>radius or math.abs(a.state.position.Z-b.state.position.Z)>radius then return nil end
 local ax,az,bx,bz=axes(a); local cx,cz,dx,dz=axes(b)
 local px,pz=a.state.position.X-b.state.position.X,a.state.position.Z-b.state.position.Z
 local best,nx,nz=math.huge,0,0
 for _,axis in {{ax,az},{bx,bz},{cx,cz},{dx,dz}} do
  local x,z=axis[1],axis[2]; local distance=dot(px,pz,x,z)
  local overlap=extent(a,x,z)+extent(b,x,z)-math.abs(distance)
  if overlap < -(C.Skin+(margin or 0)) then return nil end
  if overlap<best then best=overlap; local sign=if distance>=0 then 1 else -1; nx=x*sign; nz=z*sign end
 end
 return nx,nz,math.max(0,best),math.max(0,-best)
end
local function feature(r,nx,nz,minimum)
 local ax,az,bx,bz=axes(r); local points={}; local best=if minimum then math.huge else -math.huge
 for _,sx in {-1,1} do for _,sz in {-1,1} do
  local x=r.state.position.X+ax*r.halfX*sx+bx*r.halfZ*sz
  local z=r.state.position.Z+az*r.halfX*sx+bz*r.halfZ*sz
  local d=dot(x,z,nx,nz)
  if (minimum and d<best-1e-7) or (not minimum and d>best+1e-7) then best=d; points={{x=x,z=z}}
  elseif math.abs(d-best)<1e-7 then table.insert(points,{x=x,z=z}) end
 end end
 return points,best
end
local function manifold(a,b,dt)
 local margin=(math.abs(a.state.angularVelocity.Y)*math.sqrt(a.halfX^2+a.halfZ^2)+(if b.fixed then 0 else math.abs(b.state.angularVelocity.Y)*math.sqrt(b.halfX^2+b.halfZ^2)))*(dt or 0)
 local nx,nz,depth,gap=separating(a,b,margin); if not nx then return nil end
 local fa,da=feature(a,nx,nz,true); local fb,db
 if b.plane then
  db=b.plane.offset; fb={}
  for _,p in fa do local shift=db-dot(p.x,p.z,nx,nz); table.insert(fb,{x=p.x+nx*shift,z=p.z+nz*shift}) end
 else fb,db=feature(b,nx,nz,false) end
 local tx,tz=-nz,nx
 local function interval(f)
  local low,high=math.huge,-math.huge
  for _,p in f do local t=dot(p.x,p.z,tx,tz); low=math.min(low,t); high=math.max(high,t) end
  return low,high
 end
 local al,ah=interval(fa); local bl,bh=interval(fb)
 local low,high=math.max(al,bl),math.min(ah,bh)
 if low>high then local middle=(low+high)/2; low=middle; high=middle end
 local plane=(da+db)/2; local out={}
 local function add(t)
  table.insert(out,{a=a,b=b,nx=nx,nz=nz,x=nx*plane+tx*t,z=nz*plane+tz*t,normalImpulse=0,tangentImpulse=0,depth=depth,allowedSpeed=if gap>0 and dt and dt>0 then gap/dt else 0})
 end
 add(low); if high-low>0.001 then add(high) end
 return out
end
local function velocity(r,x,z)
 if r.fixed then return 0,0 end
 local s=r.state; local v=Motion.ensure(s); local w=s.angularVelocity.Y
 return v.X+w*(z-s.position.Z),v.Z-w*(x-s.position.X)
end
local function inverse(r) return if r.fixed then 0 else 1/r.state.motionMass,if r.fixed then 0 else 1/r.state.yawInertia end
local function effective(r,x,z,nx,nz)
 local mass,inertia=inverse(r); local p=r.state.position
 local cross=(z-p.Z)*nx-(x-p.X)*nz
 return mass+cross*cross*inertia
end
local function push(r,x,z,jx,jz)
 if not r.fixed then Motion.impulse(r.state,Vector3.new(jx,0,jz),Vector3.new(x,r.state.position.Y,z)) end
end
local function normalSpeed(c)
 local ax,az=velocity(c.a,c.x,c.z); local bx,bz=velocity(c.b,c.x,c.z)
 return dot(ax-bx,az-bz,c.nx,c.nz)+c.allowedSpeed
end
local function normalDelta(c,j)
 local nextImpulse=math.max(0,c.normalImpulse+j); j=nextImpulse-c.normalImpulse; c.normalImpulse=nextImpulse
 push(c.a,c.x,c.z,c.nx*j,c.nz*j); push(c.b,c.x,c.z,-c.nx*j,-c.nz*j)
end
local function solveNormal(c)
 local den=effective(c.a,c.x,c.z,c.nx,c.nz)+effective(c.b,c.x,c.z,c.nx,c.nz)
 if den>0 then normalDelta(c,math.max(0,c.normalImpulse-normalSpeed(c)/den)-c.normalImpulse) end
end
-- Two-point normal block avoids introducing artificial spin on a centered
-- face impact (especially a large tank hitting a narrow pillar).
local function solveBlock(a,b)
 local function cross(r,c) local p=r.state.position; return (c.z-p.Z)*c.nx-(c.x-p.X)*c.nz end
 local ma,ia=inverse(a.a); local mb,ib=inverse(a.b)
 local a1,a2,b1,b2=cross(a.a,a),cross(a.a,b),cross(a.b,a),cross(a.b,b)
 local k11=ma+mb+a1*a1*ia+b1*b1*ib
 local k22=ma+mb+a2*a2*ia+b2*b2*ib
 local k12=ma+mb+a1*a2*ia+b1*b2*ib
 local det=k11*k22-k12*k12
 if det<=1e-12 then solveNormal(a); solveNormal(b); return end
 local v1,v2=normalSpeed(a),normalSpeed(b)
 local d1,d2=(-k22*v1+k12*v2)/det,(k12*v1-k11*v2)/det
 local x1,x2=a.normalImpulse+d1,b.normalImpulse+d2
 if x1<0 or x2<0 then
  d1=-a.normalImpulse; d2=(-v2-k12*d1)/k22
  if b.normalImpulse+d2>=0 and v1+k11*d1+k12*d2>=-1e-8 then
   -- first contact inactive
  else
   d2=-b.normalImpulse; d1=(-v1-k12*d2)/k11
   if a.normalImpulse+d1<0 or v2+k12*d1+k22*d2< -1e-8 then d1=-a.normalImpulse; d2=-b.normalImpulse end
  end
 end
 normalDelta(a,d1); normalDelta(b,d2)
end
local function solveFriction(c)
 local tx,tz=-c.nz,c.nx
 local ax,az=velocity(c.a,c.x,c.z); local bx,bz=velocity(c.b,c.x,c.z)
 local den=effective(c.a,c.x,c.z,tx,tz)+effective(c.b,c.x,c.z,tx,tz)
 if den<=0 then return end
 local limit=C.Friction*c.normalImpulse
 local nextImpulse=math.clamp(c.tangentImpulse-dot(ax-bx,az-bz,tx,tz)/den,-limit,limit)
 local delta=nextImpulse-c.tangentImpulse; c.tangentImpulse=nextImpulse
 push(c.a,c.x,c.z,tx*delta,tz*delta); push(c.b,c.x,c.z,-tx*delta,-tz*delta)
end
local function correct(r,x,z)
 if r.fixed then return end
 local previous=r.state.position
 r.state.position+=Vector3.new(x,0,z)
 -- Record the actual applied displacement, including Vector3 quantization.
 r.state.motionCorrection=(r.state.motionCorrection or Vector3.zero)+(r.state.position-previous)
end
local function eachPair(bodies,statics,visit)
 for i,a in bodies do
  for j=i+1,#bodies do visit(a,bodies[j]) end
  for _,b in statics do visit(a,b) end
 end
end
local function resolve(bodies,statics,dt)
 local contacts={}
 eachPair(bodies,statics,function(a,b)
  local found=manifold(a,b,dt); if found then table.insert(contacts,found) end
 end)
 if #contacts==0 then return end -- open space needs no positional solver passes
 for _=1,C.Iterations do for _,group in contacts do
  if #group==2 then solveBlock(group[1],group[2]) else solveNormal(group[1]) end
  for _,c in group do solveFriction(c) end
 end end
 -- Split positional correction never feeds artificial separation energy into v.
 for _=1,C.Iterations do
  eachPair(bodies,statics,function(a,b)
   local nx,nz,depth=separating(a,b)
   if nx and depth>C.Skin then
    local ia=inverse(a); local ib=inverse(b); local sum=ia+ib
    if sum>0 then local correction=if b.plane then (depth+C.Skin)/sum else (depth-C.Skin)*0.8/sum
     correct(a,nx*correction*ia,nz*correction*ia); correct(b,-nx*correction*ib,-nz*correction*ib)
    end
   end
  end)
 end
end
-- Continuous translational SAT. Yaw is subdivided deterministically; its
-- swept envelope expansion prevents a rotating corner crossing unnoticed.
local function impactTime(a,b,dt)
 if b.plane then
  local p=b.plane; local s=a.state; local v=Motion.ensure(s)
  local gap=dot(s.position.X,s.position.Z,p.nx,p.nz)-p.offset-extent(a,p.nx,p.nz)
  local closing=dot(v.X,v.Z,p.nx,p.nz)-math.abs(s.angularVelocity.Y)*math.sqrt(a.halfX^2+a.halfZ^2)
  if gap<=C.Skin or closing>=0 then return nil end
  local t=gap/(-closing*dt); return if t>1e-8 and t<=1 then t else nil
 end
 if not vertical(a,b) or separating(a,b) then return nil end
 local ax,az,bx,bz=axes(a); local cx,cz,dx,dz=axes(b)
 local av=Motion.ensure(a.state); local bv=if b.fixed then Vector3.zero else Motion.ensure(b.state)
 local px,pz=a.state.position.X-b.state.position.X,a.state.position.Z-b.state.position.Z
 local vx,vz=(av.X-bv.X)*dt,(av.Z-bv.Z)*dt
 local expansion=(math.abs(a.state.angularVelocity.Y)*math.sqrt(a.halfX^2+a.halfZ^2)+(if b.fixed then 0 else math.abs(b.state.angularVelocity.Y)*math.sqrt(b.halfX^2+b.halfZ^2)))*dt
 local radius=a.halfX+a.halfZ+b.halfX+b.halfZ+expansion
 if (px>radius and px+vx>radius) or (px< -radius and px+vx< -radius) or (pz>radius and pz+vz>radius) or (pz< -radius and pz+vz< -radius) then return nil end
 local enter,exit=0,1
 for _,axis in {{ax,az},{bx,bz},{cx,cz},{dx,dz}} do
  local x,z=axis[1],axis[2]; local p,v=dot(px,pz,x,z),dot(vx,vz,x,z)
  local radius=extent(a,x,z)+extent(b,x,z)+expansion
  if math.abs(v)<1e-10 then if math.abs(p)>radius then return nil end
  else
   local t1,t2=(-radius-p)/v,(radius-p)/v
   if t1>t2 then t1,t2=t2,t1 end
   enter=math.max(enter,t1); exit=math.min(exit,t2)
   if enter>exit then return nil end
  end
 end
 if enter<1e-8 or enter>1 then return nil end
 return enter
end
function C.body(id,state,chassis)
 Motion.ensure(state)
 return {id=id,state=state,halfX=(chassis.CollisionWidth or chassis.Radius*2)/2,halfZ=(chassis.CollisionLength or chassis.Radius*2)/2,bottom=chassis.HitboxHeight-chassis.Hitbox.Y/2,top=chassis.HitboxHeight+chassis.Hitbox.Y/2}
end
function C.box(id,position,halfX,halfZ,bottom,top,yaw)
 return {id=id,fixed=true,state={position=position,yaw=yaw or 0,linearVelocity=Vector3.zero,angularVelocity=Vector3.zero},halfX=halfX,halfZ=halfZ,bottom=bottom,top=top}
end
function C.obstacles(environment,mapSize,radius)
 local cached=environment and environment.motionObstacles
 if cached and cached.width==(mapSize and mapSize.X) and cached.depth==(mapSize and mapSize.Y) then return cached.records end
 local out={}
 if mapSize then
  local x,z=mapSize.X/2,mapSize.Y/2; local thick=100
  table.insert(out,C.box("boundary:e",Vector3.new(x+thick,0,0),thick,z+thick,-math.huge,math.huge))
  out[#out].plane={nx=-1,nz=0,offset=-x}
  table.insert(out,C.box("boundary:w",Vector3.new(-x-thick,0,0),thick,z+thick,-math.huge,math.huge))
  out[#out].plane={nx=1,nz=0,offset=-x}
  table.insert(out,C.box("boundary:n",Vector3.new(0,0,-z-thick),x+thick,thick,-math.huge,math.huge))
  out[#out].plane={nx=0,nz=1,offset=-z}
  table.insert(out,C.box("boundary:s",Vector3.new(0,0,z+thick),x+thick,thick,-math.huge,math.huge))
  out[#out].plane={nx=0,nz=-1,offset=-z}
 end
 for i,t in environment and environment.trees or {} do table.insert(out,C.box("tree:"..i,Vector3.new(t.x,0,t.z),t.radius,t.radius,0,t.height or math.huge)) end
 if environment then environment.motionObstacles={width=mapSize and mapSize.X,depth=mapSize and mapSize.Y,records=out} end
 return out
end
function C.solve(bodies,statics,dt)
 table.sort(bodies,function(a,b) return a.id<b.id end); table.sort(statics,function(a,b) return a.id<b.id end)
 local substeps=1
 for _,r in bodies do
  local s=r.state
  substeps=math.max(substeps,math.ceil(math.abs(s.angularVelocity.Y)*dt/0.08))
  local previous=s.motionStepStart
  if previous then
   s.position=Vector3.new(previous.X,s.position.Y,previous.Z); s.yaw=s.motionYawStart
   s.motionForwardTravel=s.motionForwardStart or 0; s.motionYawTravel=s.motionYawTravelStart or 0
  end
 end
 substeps=math.min(C.MaxSubsteps,substeps)
 for _=1,substeps do
  resolve(bodies,statics,dt/substeps)
  local remaining=dt/substeps
  for event=1,C.MaxEvents do
   local time=1
   eachPair(bodies,statics,function(a,b) local t=impactTime(a,b,remaining); if t then time=math.min(time,t) end end)
   local advance=remaining*time
   for _,r in bodies do Motion.integrateHorizontal(r.state,advance) end
   resolve(bodies,statics)
   remaining-=advance
   if time>=1 or remaining<1e-9 then break end
   if event==C.MaxEvents then for _,r in bodies do r.state.motionContactLimited=(r.state.motionContactLimited or 0)+1 end end
  end
 end
 for _,r in bodies do Motion.sync(r.state) end
end
return C
