-- Deterministic planar rigid contacts for the existing scripted simulation.
-- Records are generic body+box geometry; no tank names, Instances or tasks.
local Motion=require(script.Parent.VehicleMotion)
local WorldGeometry=require(script.Parent.WorldObjectGeometry)
local C={Skin=0.0001,Iterations=10,MaxEvents=12,MaxSubsteps=16,Friction=0.15}
local CorrectionReserve=2
local function dot(x,z,a,b) return x*a+z*b end
local function axes(r) local c,s=math.cos(r.state.yaw),math.sin(r.state.yaw); return c,-s,s,c end
local function boxExtent(r,x,z,ax,az,bx,bz)
 return math.abs(dot(ax,az,x,z))*r.halfX+math.abs(dot(bx,bz,x,z))*r.halfZ
end
local function extent(r,x,z)
 local ax,az,bx,bz=axes(r)
 return boxExtent(r,x,z,ax,az,bx,bz)
end
local function angularReach(r)
 return math.abs(r.state.angularVelocity.Y)*(r.sweepRadius or math.sqrt(r.halfX^2+r.halfZ^2))
end
local function polygonAxes(a,b)
 local ax,az,bx,bz=axes(a);local out={{ax,az},{bx,bz}}
 for i,p in b.polygon do
  local q=b.polygon[i%#b.polygon+1];local x,z=q.z-p.z,p.x-q.x;local length=math.sqrt(x*x+z*z)
  if length>1e-9 then table.insert(out,{x/length,z/length})end
 end
 return out
end
local function interval(r,x,z)
 local center=dot(r.state.position.X,r.state.position.Z,x,z)
 if not r.polygon then local radius=extent(r,x,z);return center-radius,center+radius end
 local low,high=math.huge,-math.huge
 for _,p in r.polygon do local d=center+dot(p.x,p.z,x,z);low=math.min(low,d);high=math.max(high,d)end
 return low,high
end
local function vertical(a,b)
 if b.surface and WorldGeometry.canTraverse(b.surface,a.state.position,a.halfX+a.halfZ,a.state) then return false end
 local ay=a.state.position.Y; local by=b.state.position.Y
 return ay+a.top>by+b.bottom+C.Skin and by+b.top>ay+a.bottom+C.Skin
end
local function separating(a,b,margin,stats)
 if b.plane then
  if stats then stats.narrowTests+=1 end
  local p=b.plane; local gap=dot(a.state.position.X,a.state.position.Z,p.nx,p.nz)-p.offset-extent(a,p.nx,p.nz)
  if gap>C.Skin+(margin or 0) then return nil end
  return p.nx,p.nz,math.max(0,-gap),math.max(0,gap)
 end
 if not vertical(a,b) then return nil end
 local radius=a.halfX+a.halfZ+b.halfX+b.halfZ+(margin or 0)+C.Skin
 if math.abs(a.state.position.X-b.state.position.X)>radius or math.abs(a.state.position.Z-b.state.position.Z)>radius then return nil end
 if stats then stats.narrowTests+=1 end
 if b.polygon then
  local best,nx,nz=math.huge,0,0
  for _,axis in polygonAxes(a,b)do
   local x,z=axis[1],axis[2];local al,ah=interval(a,x,z);local bl,bh=interval(b,x,z)
   local plus,minus=bh-al,ah-bl
   if math.min(plus,minus)< -(C.Skin+(margin or 0)) then return nil end
   if plus<best then best=plus;nx=x;nz=z end
   if minus<best then best=minus;nx=-x;nz=-z end
  end
  return nx,nz,math.max(0,best),math.max(0,-best)
 end
 if stats then stats.boxSatTests+=1 end
 local ax,az,bx,bz=axes(a); local cx,cz,dx,dz=axes(b)
 local px,pz=a.state.position.X-b.state.position.X,a.state.position.Z-b.state.position.Z
 local best,nx,nz=math.huge,0,0
 for i=1,4 do
  local x=if i==1 then ax elseif i==2 then bx elseif i==3 then cx else dx
  local z=if i==1 then az elseif i==2 then bz elseif i==3 then cz else dz
  local distance=dot(px,pz,x,z)
  local overlap=boxExtent(a,x,z,ax,az,bx,bz)+boxExtent(b,x,z,cx,cz,dx,dz)-math.abs(distance)
  if overlap < -(C.Skin+(margin or 0)) then return nil end
  if overlap<best then best=overlap; local sign=if distance>=0 then 1 else -1; nx=x*sign; nz=z*sign end
 end
 return nx,nz,math.max(0,best),math.max(0,-best)
end
local function feature(r,nx,nz,minimum)
 local ax,az,bx,bz=axes(r); local points={}; local best=if minimum then math.huge else -math.huge
 if r.polygon then
  for _,p in r.polygon do
   local x,z=r.state.position.X+p.x,r.state.position.Z+p.z;local d=dot(x,z,nx,nz)
   if (minimum and d<best-1e-7) or (not minimum and d>best+1e-7) then best=d;points={{x=x,z=z}}
   elseif math.abs(d-best)<1e-7 then table.insert(points,{x=x,z=z})end
  end
  return points,best
 end
 for sx=-1,1,2 do for sz=-1,1,2 do
  local x=r.state.position.X+ax*r.halfX*sx+bx*r.halfZ*sz
  local z=r.state.position.Z+az*r.halfX*sx+bz*r.halfZ*sz
  local d=dot(x,z,nx,nz)
  if (minimum and d<best-1e-7) or (not minimum and d>best+1e-7) then best=d; points={{x=x,z=z}}
  elseif math.abs(d-best)<1e-7 then table.insert(points,{x=x,z=z}) end
 end end
 return points,best
end
local function manifold(a,b,dt,stats)
 local margin=(angularReach(a)+(if b.fixed then 0 else angularReach(b)))*(dt or 0)
 local nx,nz,depth,gap=separating(a,b,margin,stats); if not nx then return nil end
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
local function inverse(r)
 if r.fixed then return 0,0 end
 return r.inverseMass or 1/r.state.motionMass,r.inverseInertia or 1/r.state.yawInertia
end
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
local function contains(list,minX,maxX,minZ,maxZ)
 return minX>=list.minX and maxX<=list.maxX and minZ>=list.minZ and maxZ<=list.maxZ
end
local function candidates(a,list,statics,dt,sweep,stats)
 local p=a.state.position
 local dx,dz=0,0
 if sweep then
  local v=Motion.ensure(a.state)
  dx,dz=v.X*dt,v.Z*dt
 end
 -- Match the solver's existing L1 center reach, including speculative angular
 -- contacts. The reserve allows small positional corrections to reuse the list.
 local reach=a.halfX+a.halfZ+C.Skin+angularReach(a)*dt
 local minX,maxX=p.X+math.min(0,dx)-reach,p.X+math.max(0,dx)+reach
 local minZ,maxZ=p.Z+math.min(0,dz)-reach,p.Z+math.max(0,dz)+reach
 if contains(list,minX,maxX,minZ,maxZ) then return end
 minX,maxX=minX-CorrectionReserve,maxX+CorrectionReserve
 minZ,maxZ=minZ-CorrectionReserve,maxZ+CorrectionReserve
 list.minX,list.maxX,list.minZ,list.maxZ=minX,maxX,minZ,maxZ
 table.clear(list.indices)
 if stats then stats.candidateChecks+=#statics;stats.rebuilds+=1 end
 for i,b in statics do
  if b.configurationOnly and a.ignoreConfigurationZones then continue end
  local inside
  if not b.fixed then
   inside=true
  elseif b.plane then
   local plane=b.plane
   local x=if plane.nx>=0 then minX else maxX
   local z=if plane.nz>=0 then minZ else maxZ
   inside=math.abs(plane.nx)+math.abs(plane.nz)<1 or dot(x,z,plane.nx,plane.nz)<=plane.offset
  else
   local pos=b.state.position
   local radius=b.halfX+b.halfZ
   inside=pos.X+radius>=minX and pos.X-radius<=maxX and pos.Z+radius>=minZ and pos.Z-radius<=maxZ
  end
  if inside then table.insert(list.indices,i) end
 end
end
local function eachPair(bodies,statics,lists,dt,sweep,correction,visit,stats)
 for i,a in bodies do
  for j=i+1,#bodies do
   if stats then stats.pairVisits+=1 end
   visit(a,bodies[j])
  end
  if #statics==0 then continue end
  local list=lists[i]
  candidates(a,list,statics,dt,sweep,stats)
  local cursor=1
  while cursor<=#list.indices do
   local index=list.indices[cursor]
   if stats then stats.pairVisits+=1 end
   local corrected=visit(a,statics[index])
   cursor+=1
   if correction and corrected then
    local p=a.state.position
    local reach=a.halfX+a.halfZ+C.Skin
    if not contains(list,p.X-reach,p.X+reach,p.Z-reach,p.Z+reach) then
     if stats then stats.correctionRebuilds+=1 end
     candidates(a,list,statics,0,false,stats)
     -- Continue in the original pair order. Earlier constraints are revisited
     -- on the next correction pass, just as in the exhaustive solver.
     cursor=1
     while list.indices[cursor] and list.indices[cursor]<=index do cursor+=1 end
    end
   end
  end
 end
end
local function resolve(bodies,statics,lists,dt,stats)
 local contacts={}
 eachPair(bodies,statics,lists,dt or 0,dt~=nil,false,function(a,b)
  local found=manifold(a,b,dt,stats)
  if found then
   table.insert(contacts,found)
   if stats then stats.contacts+=#found end
  end
 end,stats)
 if #contacts==0 then return end -- open space needs no positional solver passes
 for _=1,C.Iterations do for _,group in contacts do
  if #group==2 then solveBlock(group[1],group[2]) else solveNormal(group[1]) end
  for _,c in group do solveFriction(c) end
 end end
 if lists.trackContacts then
  for _,group in contacts do
   local first,second=group[1],group[2]
   if (first.a.trackContacts or first.b.trackContacts) and
    (first.depth>C.Skin or first.normalImpulse>1e-6 or (second and second.normalImpulse>1e-6)) then
    if first.a.trackContacts then first.a.state.motionDebugContact=first.b.id end
    if first.b.trackContacts then first.b.state.motionDebugContact=first.a.id end
   end
  end
 end
 -- Split positional correction never feeds artificial separation energy into v.
 for _=1,C.Iterations do
  local needsCorrection=false
  if stats then stats.correctionPasses+=1 end
  eachPair(bodies,statics,lists,0,false,true,function(a,b)
   local nx,nz,depth=separating(a,b,nil,stats)
   if nx and depth>C.Skin then
    local ia=inverse(a); local ib=inverse(b); local sum=ia+ib
    if sum>0 then
     needsCorrection=true
     local correction=if b.plane then (depth+C.Skin)/sum else (depth-C.Skin)*0.8/sum
     correct(a,nx*correction*ia,nz*correction*ia); correct(b,-nx*correction*ib,-nz*correction*ib)
     return true
    end
   end
  end,stats)
  if not needsCorrection then break end
 end
end
-- Find the first rotating corner to reach a boundary. The angular speed
-- bound can reject a miss, but using it as the impact time can repeatedly
-- schedule events that have no contact to resolve.
local function planeImpact(a,p,dt)
 local s=a.state; local v=Motion.ensure(s)
 local center=dot(s.position.X,s.position.Z,p.nx,p.nz)-p.offset
 local speed=dot(v.X,v.Z,p.nx,p.nz)
 local omega=s.angularVelocity.Y
 local gap=center-extent(a,p.nx,p.nz)
 local closing=speed-angularReach(a)
 if gap<=C.Skin then return nil end
 if omega==0 then
  if speed>=0 then return nil end
  local fraction=gap/(-speed*dt)
  return if fraction>1e-8 and fraction<=1 then fraction else nil
 end
 local skin=C.Skin/2
 if gap+closing*dt>skin then return nil end
 local ax,az,bx,bz=axes(a)
 local radius=a.sweepRadius
 local period=2*math.pi/math.abs(omega)
 local rate=speed/(omega*radius)
 local best=dt
 local hit=false
 for sx=-1,1,2 do for sz=-1,1,2 do
  local x=ax*a.halfX*sx+bx*a.halfZ*sz
  local z=az*a.halfX*sx+bz*a.halfZ*sz
  local q=dot(x,z,p.nx,p.nz)
  local tangent=dot(z,-x,p.nx,p.nz)
  local function at(t)
   local angle=omega*t
   return center+speed*t+q*math.cos(angle)+tangent*math.sin(angle)
  end
  local low,high=0,best
  if math.abs(rate)<1 then
   -- At a local minimum the corner's normal velocity is zero and its
   -- normal acceleration is positive. Later minima differ only by drift.
   local angle=-math.acos(-rate)-math.atan2(q,tangent)
   local first=(angle/omega)%period
   if first<=high then
    local value=at(first)
    local candidate=first
    if value>skin and speed<0 then
     candidate+=math.ceil((value-skin)/(-speed*period))*period
    end
    if candidate<=high and at(candidate)<=skin then
     low=math.max(0,candidate-period);high=candidate
    end
   end
  end
  if at(high)<=skin then
   for _=1,24 do
    local middle=(low+high)/2
    if at(middle)<=skin then high=middle else low=middle end
   end
   best=high;hit=true
  end
 end end
 return if hit then best/dt else nil
end
-- Continuous translational SAT. Yaw is subdivided deterministically; its
-- swept envelope expansion prevents a rotating corner crossing unnoticed.
local function impactTime(a,b,dt,stats)
 if b.plane then
  if stats then stats.narrowTests+=1 end
  return planeImpact(a,b.plane,dt)
 end
 if not vertical(a,b) or separating(a,b,nil,stats) then return nil end
 local ax,az,bx,bz=axes(a); local cx,cz,dx,dz=axes(b)
 local av=Motion.ensure(a.state); local bv=if b.fixed then Vector3.zero else Motion.ensure(b.state)
 local px,pz=a.state.position.X-b.state.position.X,a.state.position.Z-b.state.position.Z
 local vx,vz=(av.X-bv.X)*dt,(av.Z-bv.Z)*dt
 local expansion=(angularReach(a)+(if b.fixed then 0 else angularReach(b)))*dt
 local radius=a.halfX+a.halfZ+b.halfX+b.halfZ+expansion
 if (px>radius and px+vx>radius) or (px< -radius and px+vx< -radius) or (pz>radius and pz+vz>radius) or (pz< -radius and pz+vz< -radius) then return nil end
 if stats then stats.narrowTests+=1 end
 local enter,exit=0,1
 if b.polygon then
  for _,axis in polygonAxes(a,b)do
   local x,z=axis[1],axis[2];local al,ah=interval(a,x,z);local bl,bh=interval(b,x,z);local v=dot(vx,vz,x,z)
   if math.abs(v)<1e-10 then if ah+expansion<bl or al-expansion>bh then return nil end
   else
    local t1,t2=(bl-ah-expansion)/v,(bh-al+expansion)/v
    if t1>t2 then t1,t2=t2,t1 end
    enter=math.max(enter,t1);exit=math.min(exit,t2);if enter>exit then return nil end
   end
  end
  return if enter>=1e-8 and enter<=1 then enter else nil
 end
 if stats then stats.boxSatTests+=1 end
 for i=1,4 do
  local x=if i==1 then ax elseif i==2 then bx elseif i==3 then cx else dx
  local z=if i==1 then az elseif i==2 then bz elseif i==3 then cz else dz
  local p,v=dot(px,pz,x,z),dot(vx,vz,x,z)
  local radius=boxExtent(a,x,z,ax,az,bx,bz)+boxExtent(b,x,z,cx,cz,dx,dz)+expansion
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
function C.polygon(id,points,bottom,top,wall)
 local sorted={};for _,p in points do table.insert(sorted,{x=p.X,z=p.Z})end
 table.sort(sorted,function(a,b)return a.x<b.x or (a.x==b.x and a.z<b.z)end)
 local function turn(a,b,c)return (b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x)end
 local hull={}
 for _,p in sorted do while #hull>=2 and turn(hull[#hull-1],hull[#hull],p)<=1e-9 do table.remove(hull)end;table.insert(hull,p)end
 local lower=#hull
 for i=#sorted-1,1,-1 do local p=sorted[i];while #hull>lower and turn(hull[#hull-1],hull[#hull],p)<=1e-9 do table.remove(hull)end;table.insert(hull,p)end
 table.remove(hull)
 if #hull<3 then
  if wall and #hull==2 then
   local a,b=hull[1],hull[2];local dx,dz=b.x-a.x,b.z-a.z;local length=math.sqrt(dx*dx+dz*dz)
   if length>1e-9 then
    local nx,nz=-dz/length*C.Skin*5,dx/length*C.Skin*5
    return C.polygon(id,{Vector3.new(a.x+nx,0,a.z+nz),Vector3.new(b.x+nx,0,b.z+nz),Vector3.new(b.x-nx,0,b.z-nz),Vector3.new(a.x-nx,0,a.z-nz)},bottom,top)
   end
  end
  return nil
 end
 local lowX,lowZ,highX,highZ=math.huge,math.huge,-math.huge,-math.huge
 for _,p in hull do lowX=math.min(lowX,p.x);lowZ=math.min(lowZ,p.z);highX=math.max(highX,p.x);highZ=math.max(highZ,p.z)end
 local center=Vector3.new((lowX+highX)/2,0,(lowZ+highZ)/2)
 local body=C.box(id,center,(highX-lowX)/2,(highZ-lowZ)/2,bottom,top)
 body.polygon={};for _,p in hull do table.insert(body.polygon,{x=p.x-center.X,z=p.z-center.Z})end
 return body
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
 for _,r in environment and environment.playground and environment.playground.staticBoxes or{}do
  table.insert(out,C.box(r.id,Vector3.new(r.x,r.y,r.z),r.sx/2,r.sz/2,-r.sy/2,r.sy/2))
 end
 for _,r in environment and environment.playground and environment.playground.configurationZones or{}do
  local zone=C.box(r.id,Vector3.new(r.x,r.y,r.z),r.halfX,r.halfZ,-math.huge,math.huge)
  zone.configurationOnly=true
  table.insert(out,zone)
 end
 local course=environment and environment.playground and environment.playground.course
 for index,area in course and course.areas or {} do
  local zone=C.box("course:boundary:"..index,Vector3.new((area.x0+area.x1)/2,0,(area.z0+area.z1)/2),(area.x1-area.x0)/2,(area.z1-area.z0)/2,-math.huge,math.huge)
  zone.configurationOnly=true
  table.insert(out,zone)
 end
 for i,t in environment and environment.trees or {} do table.insert(out,C.box("tree:"..i,Vector3.new(t.x,0,t.z),t.radius,t.radius,0,t.height or math.huge)) end
 if environment then environment.motionObstacles={width=mapSize and mapSize.X,depth=mapSize and mapSize.Y,records=out} end
 return out
end
function C.solve(bodies,statics,dt,stats)
 table.sort(bodies,function(a,b) return a.id<b.id end); table.sort(statics,function(a,b) return a.id<b.id end)
 if stats then
  stats.candidateChecks=0;stats.pairVisits=0;stats.narrowTests=0;stats.boxSatTests=0;stats.contacts=0
  stats.correctionPasses=0;stats.rebuilds=0;stats.correctionRebuilds=0
 end
 local substeps,lists=1,{}
 for i,r in bodies do
  local s=r.state
  if r.trackContacts then
   lists.trackContacts=true
   s.motionDebugContact=nil;s.motionDebugLimitedBy=nil;s.motionDebugLostTime=0
  end
  Motion.ensure(s)
  r.sweepRadius=math.sqrt(r.halfX^2+r.halfZ^2)
  r.inverseMass,r.inverseInertia=1/s.motionMass,1/s.yawInertia
  lists[i]={indices={},minX=math.huge,maxX=-math.huge,minZ=math.huge,maxZ=-math.huge}
  substeps=math.max(substeps,math.ceil(math.abs(s.angularVelocity.Y)*dt/0.08))
  local previous=s.motionStepStart
  if previous then
   s.position=Vector3.new(previous.X,s.position.Y,previous.Z); s.yaw=s.motionYawStart
   s.motionForwardTravel=s.motionForwardStart or 0; s.motionYawTravel=s.motionYawTravelStart or 0
  end
 end
 substeps=math.min(C.MaxSubsteps,substeps)
 for _=1,substeps do
  resolve(bodies,statics,lists,dt/substeps,stats)
  local remaining=dt/substeps
  for event=1,C.MaxEvents do
   local time=1
   local eventA,eventB
   eachPair(bodies,statics,lists,remaining,true,false,function(a,b)
    local t=impactTime(a,b,remaining,stats)
    if t and t<time then time=t;eventA,eventB=a.id,b.id end
   end,stats)
   local advance=remaining*time
   for _,r in bodies do Motion.integrateHorizontal(r.state,advance) end
   resolve(bodies,statics,lists,nil,stats)
   remaining-=advance
   if time>=1 or remaining<1e-9 then break end
   if event==C.MaxEvents then
    for _,r in bodies do
     local s=r.state
     s.motionContactLimited=(s.motionContactLimited or 0)+1
     if r.trackContacts then
      s.motionDebugLostTime+=remaining
      s.motionDebugLimitedBy=eventA.." / "..eventB
     end
    end
   end
  end
 end
 for _,r in bodies do Motion.sync(r.state) end
end
return C
