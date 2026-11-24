-- Imported scenery uses the same fixed-body solver and projectile hit stream as
-- arena cover. Native mesh physics stays disabled; trusted fitted proxy cells query.
local Contacts=require(game.ReplicatedStorage.Shared.VehicleContacts)
local Geometry=require(game.ReplicatedStorage.Shared.WorldObjectGeometry)
local Visual=require(game.ReplicatedStorage.Shared.AssetGeometry)
local Fit=require(script.Parent.MeshCollisionFit)
local Footprint=require(game.ReplicatedStorage.Shared.FootprintSupport)
local Materials=require(game.ReplicatedStorage.Shared.TerrainMaterials)
local Motion=require(game.ReplicatedStorage.Shared.WorldMotion)
local VehicleMotion=require(game.ReplicatedStorage.Shared.VehicleMotion)
local Objects={}; Objects.__index=Objects
local Document=require(game.ReplicatedStorage.Shared.WorldEditorDocument)
local MaxKinematicCorrection=1.25
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function Objects.new()
 return setmetatable({records={},regenerating={},moving={},activeMotion={},savedMotion=setmetatable({},{__mode="k"}),byPart={},seen=setmetatable({},{__mode="k"}),effects={}},Objects)
end
function Objects:sync(record)
 local live=not record.destroyed
 for _,proxy in record.proxies do
  proxy.CanQuery=live and (record.solid or record.destructible)
  proxy:SetAttribute("ScannerGroundSupport",live and record.solid)
  if self.characterCollision then proxy.CanCollide=live and record.solid end
 end
 for part,transparency in record.visuals do part.Transparency=if live then transparency else 1 end
 record.model:SetAttribute("WorldObjectId",record.id)
 record.model:SetAttribute("Health",record.health); record.model:SetAttribute("MaxHealth",record.maxHealth)
 record.model:SetAttribute("Destructible",record.destructible); record.model:SetAttribute("Destroyed",record.destroyed)
 record.model:SetAttribute("Solid",record.solid and live)
end
function Objects:add(model,spec)
 local v=spec.interaction
 if not v then
  self:addMotion(model,spec)
  return nil
 end
 assert(type(v.solid)=="boolean" and type(v.destructible)=="boolean" and finite(v.hp) and v.hp>=0,"Invalid world-object flags/health")
 assert(v.regenerates==nil or type(v.regenerates)=="boolean","Invalid regeneration setting")
 assert(v.regenerationDelay==nil or (finite(v.regenerationDelay) and v.regenerationDelay>=0 and v.regenerationDelay<=Document.MaxRegenerationDelay),"Invalid regeneration delay")
 assert(typeof(v.fractions)=="Vector3","Missing trunk collider fractions")
 for _,n in {v.fractions.X,v.fractions.Y,v.fractions.Z} do assert(finite(n) and n>0 and n<=1,"Invalid trunk collider fraction") end
 assert(not self.records[spec.id],"Duplicate world-object ID")
 local bounds,size=Visual.measure(model)
 local width,height,depth=size.X*v.fractions.X,size.Y*v.fractions.Y,size.Z*v.fractions.Z
 assert(width>0 and height>0 and depth>0,"Trunk collider has no volume")
 local visuals={}
 for _,part in model:GetDescendants() do if part:IsA("BasePart") then visuals[part]=part.Transparency or 0 end end
 local proxies,bodies,geometries={},{},{}
 if v.fit=="faces" then
  Visual.checkFaceProfile(size,v,spec.stretch)
  assert(v.fractions.X==1 and v.fractions.Y==1 and v.fractions.Z==1,"Face profiles require full dimensions")
  geometries=Geometry.faces(Geometry.fromBox(bounds,size),v.faces,v.bases,v.walls)
  for index,geometry in geometries do
   local e=geometry.extents
   local body=Contacts.polygon("world:"..spec.id..":"..index,geometry.points,geometry.position.Y-e.Y,geometry.position.Y+e.Y,geometry.wall)
   if body then body.surface=geometry;table.insert(bodies,body)end
  end
  -- Native mesh queries provide projectile/scanner hits, rather than an
  -- oversized invisible query box. Movement uses the trusted face prisms.
  proxies=Visual.parts(model)
  for _,p in proxies do p:SetAttribute("WorldObjectId",spec.id);p:SetAttribute("ScannerObjectName",model.Name or spec.id)end
 else
 local cells=v.boxes or (if v.fit=="mesh" then Fit.profile(model) else nil)
 cells=cells or {{center={0,0,0},size={1,1,1}}}
 assert(#cells>0 and #cells<=64,"Invalid fitted collider cell count")
 for index,cell in cells do
  local c,d=cell.center,cell.size
  assert(type(c)=="table" and type(d)=="table" and #c==3 and #d==3,"Invalid fitted collider")
  for i=1,3 do assert(finite(c[i]) and math.abs(c[i])<=.501 and finite(d[i]) and d[i]>0 and d[i]<=1.001,"Invalid fitted collider dimensions") end
  local proxy=Instance.new("Part"); proxy.Name="WorldObstacleHitbox"
  proxy.Size=Vector3.new(width*d[1],height*d[2],depth*d[3])
  proxy.CFrame=bounds*CFrame.new(width*c[1],-size.Y/2+height/2+height*c[2],depth*c[3])
  proxy.Shape=Enum.PartType.Block;proxy.Anchored=true;proxy.Transparency=1
  proxy.CanCollide=false;proxy.CanTouch=false;proxy.CanQuery=false
  proxy:SetAttribute("WorldObjectId",spec.id);proxy:SetAttribute("ScannerObjectName",model.Name or spec.id);proxy.Parent=model
  local geometry=Geometry.fromBox(proxy.CFrame,proxy.Size)
  local planar=Geometry.planar(geometry,math.rad(spec.rotation.Y))
  local body=Contacts.box("world:"..spec.id..(if #cells>1 then ":"..index else ""),proxy.CFrame.Position,planar.hx,planar.hz,planar.bottom-proxy.CFrame.Position.Y,planar.top-proxy.CFrame.Position.Y,planar.yaw)
  body.surface=geometry
  table.insert(proxies,proxy);table.insert(bodies,body);table.insert(geometries,geometry)
 end
 end
 local material=Materials.fromMaterial((model.PrimaryPart or Visual.parts(model)[1]).Material)
 for _,geometry in geometries do geometry.material=material end
 local record={id=spec.id,model=model,proxy=proxies[1],proxies=proxies,body=bodies[1],bodies=bodies,geometry=geometries[1],geometries=geometries,visuals=visuals,solid=v.solid,destructible=v.destructible,regenerates=v.regenerates~=false,regenerationDelay=v.regenerationDelay or Document.DefaultRegenerationDelay,maxHealth=v.hp,health=v.hp,destroyed=v.destructible and v.hp<=0}
 for _,proxy in proxies do self.byPart[proxy]=record end
 self.records[record.id]=record
 self:addMotion(model,spec,record)
 self:sync(record); return record
end
function Objects:addMotion(model,spec,record)
 local path=spec.motion and spec.motion.enabled and Motion.compile(spec.motion)
 local r=spec.rotation
 local spin=spec.spin and Motion.compileSpin(spec.spin,CFrame.Angles(math.rad(r.X),math.rad(r.Y),math.rad(r.Z)))
 if not path and not spin then return end
 local entry={id=spec.id,model=model,record=record,path=path,spin=spin,spinClock=0,spinAngle=0,origin=spec.position,yaw=math.rad(spec.rotation.Y),pivot=model:GetPivot(),geometries={},bodies={},clock=0,radius=1}
 if spin then local bounds=Visual.measure(model);entry.spinCenter=bounds.Position end
 if record then
  record.motion=entry
  for i,geometry in record.geometries do
   local rest=table.clone(geometry)
   if geometry.vertices then rest.vertices=table.clone(geometry.vertices);rest.points=table.clone(geometry.points) end
   entry.geometries[i]=rest
   geometry.platform=entry
   entry.radius=math.max(entry.radius,(geometry.position-entry.origin).Magnitude+geometry.extents.Magnitude)
  end
  for i,body in record.bodies do
   local rest={position=body.state.position,yaw=body.state.yaw}
   if body.polygon then
    rest.points={}
    for j,p in body.polygon do rest.points[j]=Vector3.new(p.x,0,p.z) end
   end
   entry.bodies[i]=rest
  end
 end
 table.insert(self.moving,entry)
end
-- Keep the same collision cells and faces. During the contact solve only their
-- numeric poses change. Replicate the accepted native pose once per fixed step.
local function pose(entry,offset,angle,spinAngle)
 local record=entry.record
 local rotation=Motion.orientation(angle,entry.spin,spinAngle)
 local frame=Motion.frame(entry.origin,offset,angle,entry.spin,spinAngle,entry.spinCenter)
 entry.frame=frame;entry.orientation=rotation
 if not record then return end
 for i,geometry in record.geometries do
  local rest=entry.geometries[i]
  geometry.position=frame:PointToWorldSpace(rest.position)
  geometry.up=rotation:PointToWorldSpace(rest.up)
  if rest.vertices then
   for j,p in rest.vertices do geometry.vertices[j]=frame:PointToWorldSpace(p) end
   local hx,hy,hz=0,0,0
   for j,p in rest.points do
    local point=frame:PointToWorldSpace(p);geometry.points[j]=point
    local d=point-geometry.position
    hx,hy,hz=math.max(hx,math.abs(d.X)),math.max(hy,math.abs(d.Y)),math.max(hz,math.abs(d.Z))
   end
   geometry.extents=Vector3.new(hx,hy,hz)
  else
   geometry.right=rotation:PointToWorldSpace(rest.right);geometry.back=rotation:PointToWorldSpace(rest.back)
   geometry.extents=Geometry.extents(geometry)
  end
 end
 for i,body in record.bodies do
  local rest=entry.bodies[i]
  body.state.position=frame:PointToWorldSpace(rest.position)
  if entry.spin and (math.abs(entry.spin.axis.X)>1e-6 or math.abs(entry.spin.axis.Z)>1e-6) then
   -- The tank solver is planar. A conservative projection contains the
   -- tilted collider while support and projectile queries use its real pose.
   local g=body.surface
   body.state.position=g.position;body.state.yaw=0;body.polygon=nil
   body.halfX,body.halfZ=g.extents.X,g.extents.Z
   body.bottom,body.top=-g.extents.Y,g.extents.Y
  elseif rest.points then
   local hx,hz=0,0
   for j,p in rest.points do
    local v=rotation:PointToWorldSpace(p)
    body.polygon[j].x,body.polygon[j].z=v.X,v.Z
    hx,hz=math.max(hx,math.abs(v.X)),math.max(hz,math.abs(v.Z))
   end
   body.halfX,body.halfZ=hx,hz
  else
   local planar=Geometry.planar(body.surface,rest.yaw+angle+(if entry.spin then entry.spin.axis.Y*spinAngle else 0))
   body.halfX,body.halfZ,body.state.yaw=planar.hx,planar.hz,planar.yaw
  end
 end
end
local function deltaAt(entry,point)
 local delta=entry.change
 if entry.spin then
  local d=point-entry.frame.Position
  local r=entry.orientation
  local localPoint=Vector3.new(d:Dot(r.RightVector),d:Dot(r.UpVector),-d:Dot(r.LookVector))
  return entry.endFrame:PointToWorldSpace(localPoint)-point
 end
 if entry.turn==0 then return delta end
 local p=point-entry.origin-entry.offset
 local c,s=math.cos(entry.turn),math.sin(entry.turn)
 return delta+Vector3.new((c-1)*p.X+s*p.Z,0,-s*p.X+(c-1)*p.Z)
end
local function setKinematic(entry,dt)
 for _,body in entry.record.bodies do
  local p=body.state.position
  local delta=deltaAt(entry,p)
  local radius=2*(body.halfX+body.halfZ)+.5
  body.kinematic=true
  body.kinematicMinX=p.X+math.min(0,delta.X)-radius
  body.kinematicMaxX=p.X+math.max(0,delta.X)+radius
  body.kinematicMinZ=p.Z+math.min(0,delta.Z)-radius
  body.kinematicMaxZ=p.Z+math.max(0,delta.Z)+radius
  body.state.linearVelocity=delta/dt
  body.state.angularVelocity=Vector3.new(0,(entry.turn+(if entry.spin then entry.spin.axis.Y*entry.spinTurn else 0))/dt,0)
 end
end
function Objects:prepareMotion(dt)
 table.clear(self.activeMotion)
 self.motionElapsed=0
 self.motionDt=dt
 local solid=false
 for i=#self.moving,1,-1 do
  local entry=self.moving[i]
  local record=entry.record
  if not entry.model.Parent then
   if record then
    for _,proxy in record.proxies do self.byPart[proxy]=nil end
    self.records[record.id]=nil
   end
   table.remove(self.moving,i)
   continue
  end
  if record and record.destroyed then continue end
  if entry.offset==nil or dt==0 then
   local offset,yaw=Vector3.zero,nil
   if entry.path then offset,yaw=Motion.sample(entry.path,entry.clock) end
   entry.offset,entry.angle=offset,if yaw then yaw-entry.yaw else 0
   pose(entry,entry.offset,entry.angle,entry.spinAngle)
   entry.model:PivotTo(entry.frame*entry.pivot)
   if dt==0 then continue end
  end
  local offset,yaw=Vector3.zero,nil
  if entry.path then offset,yaw=Motion.sample(entry.path,entry.clock+dt) end
  local angle=if yaw then yaw-entry.yaw else entry.angle
  local turn=(angle-entry.angle+math.pi)%(2*math.pi)-math.pi
  -- Limit corner turns by the radius of the actual collision profile.
  local limit=math.min(.08,dt*math.min(4.8,15/entry.radius))
  entry.turn=math.clamp(turn,-limit,limit)
  entry.change=offset-entry.offset
  entry.previousClock=entry.clock
  if entry.path then entry.clock=(entry.clock+dt)%entry.path.period end
  entry.spinTurn=0;entry.previousSpinClock=entry.spinClock
  if entry.spin then
   local spin=entry.spin
   -- Consume at most one phase at a time, preserving the full turn before pausing.
   local advance=dt
   if entry.spinClock<spin.duration then
    local rate=2*math.pi/spin.duration
    if record and record.solid then advance=math.min(advance,limit/rate) end
    advance=math.min(advance,spin.duration-entry.spinClock)
    entry.spinTurn=advance*rate
   end
   entry.spinClock=(entry.spinClock+advance)%spin.period
   entry.endFrame=Motion.frame(entry.origin,offset,entry.angle+entry.turn,spin,entry.spinAngle+entry.spinTurn,entry.spinCenter)
  end
  if entry.change.Magnitude<1e-6 and math.abs(entry.turn)+entry.spinTurn<1e-6 then
   entry.change=nil
   continue
  end
  table.insert(self.activeMotion,entry)
  if record and record.solid then
   solid=true
   setKinematic(entry,dt)
  end
 end
 return solid
end
function Objects:advanceMotion(dt)
 self.motionElapsed+=dt
 local fraction=math.min(1,self.motionElapsed/self.motionDt)
 for _,entry in self.activeMotion do
  if entry.record and entry.record.solid then
   pose(entry,entry.offset+entry.change*fraction,entry.angle+entry.turn*fraction,entry.spinAngle+entry.spinTurn*fraction)
  end
 end
end
function Objects:finishMotion(accepted)
 for _,entry in self.activeMotion do
  local solid=entry.record and entry.record.solid
  if accepted or not solid then
   entry.offset+=entry.change
   entry.angle=(entry.angle+entry.turn+math.pi)%(2*math.pi)-math.pi
   entry.spinAngle=(entry.spinAngle+entry.spinTurn)%(2*math.pi)
   if not solid then pose(entry,entry.offset,entry.angle,entry.spinAngle) end
   entry.model:PivotTo(entry.frame*entry.pivot)
  else
   entry.clock=entry.previousClock;entry.spinClock=entry.previousSpinClock
   pose(entry,entry.offset,entry.angle,entry.spinAngle)
  end
  if solid then
   for _,body in entry.record.bodies do
    body.kinematic=nil
    body.state.linearVelocity=Vector3.zero
    body.state.angularVelocity=Vector3.zero
   end
  end
  entry.change=nil
 end
 table.clear(self.activeMotion)
end
-- Install a start pose before spawn validation. Offline callers also use this
-- to advance scenes with no tanks.
function Objects:stepMotion(dt)
 self:prepareMotion(dt)
 if #self.activeMotion>0 then
  self:advanceMotion(dt)
  self:finishMotion(true)
 end
end
local savedFields={"position","yaw","linearVelocity","angularVelocity","motionForwardTravel","motionYawTravel",
 "motionCorrection","motionDebugContact","motionDebugLimitedBy","motionDebugLostTime"}
local function advanceWorld(self,dt)
 self:advanceMotion(dt)
end
function Objects:solveContacts(bodies,obstacles,dt,terrainBlocked,supportAfter)
 local solid=self:prepareMotion(dt)
 if not solid then
  Contacts.solve(bodies,obstacles,dt)
  if #self.activeMotion>0 then self:advanceMotion(dt);self:finishMotion(true) end
  return true
 end
 for _,body in bodies do
  local state=body.state
  local saved=self.savedMotion[state]
  if not saved then saved={};self.savedMotion[state]=saved end
  for _,field in savedFields do saved[field]=state[field] end
  local platform=body.platform
  if platform and platform.change then
   local velocity=deltaAt(platform,state.motionStepStart or state.position)/dt
   body.carryVelocity=velocity
   body.carryYaw=(platform.turn+(if platform.spin then platform.spin.axis.Y*platform.spinTurn else 0))/dt
   body.platformLift=velocity.Y
   body.kinematicAffected=true
   VehicleMotion.setVelocity(state,VehicleMotion.ensure(state)+Vector3.new(velocity.X,0,velocity.Z))
   VehicleMotion.setYawVelocity(state,state.angularVelocity.Y+body.carryYaw)
  end
 end
 local accepted=Contacts.solve(bodies,obstacles,dt,nil,advanceWorld,self)
 if accepted then
  for _,body in bodies do
   local state=body.state
   if body.kinematicAffected then
    local saved=self.savedMotion[state]
    local split=(state.motionCorrection or Vector3.zero)-(saved.motionCorrection or Vector3.zero)
    if split.Magnitude>MaxKinematicCorrection or (terrainBlocked and terrainBlocked(state,body)) then accepted=false;break end
   end
  end
 end
 -- Penetration correction is positional, so a contradictory squeeze may
 -- converge poorly. Reject the kinematic tick before replicating anything.
 self:finishMotion(accepted)
 if not accepted then
  for _,body in bodies do
   local state=body.state
   local saved=self.savedMotion[state]
   for _,field in savedFields do state[field]=saved[field] end
   body.platformLift=nil;body.carryVelocity=nil;body.carryYaw=nil
   VehicleMotion.sync(state)
  end
  Contacts.solve(bodies,obstacles,dt)
  return false
 end
 for _,body in bodies do
  local carry=body.carryVelocity
  if carry then
   local state=body.state
   local v=VehicleMotion.ensure(state)
   if supportAfter(body)==body.platform then
    VehicleMotion.setVelocity(state,v-Vector3.new(carry.X,0,carry.Z))
    VehicleMotion.setYawVelocity(state,state.angularVelocity.Y-body.carryYaw)
   else
    VehicleMotion.setVelocity(state,v+Vector3.new(0,carry.Y,0))
   end
  end
 end
 return true
end
local function liveSolid(record)
 return record.solid and not record.destroyed and record.proxy.Parent and (not record.motion or record.model.Parent)
end
function Objects:footprintSupport(position,yaw,shape)
 local boxes={}
 for _,record in self.records do
  if liveSolid(record) then
   for _,box in record.geometries do table.insert(boxes,box)end
  end
 end
 if #boxes>0 then return Footprint.solve(boxes,position,yaw,shape) end
end
function Objects:support(x,z,maxHeight)
 local height,surface
 for _,record in self.records do
  if liveSolid(record) then
   for _,geometry in record.geometries do
    local y=Geometry.support(geometry,x,z,maxHeight)
    if y and (not height or y>height) then height=y;surface=geometry end
   end
  end
 end
 return height,surface
end
function Objects:obstacles()
 local out={}
 for _,record in self.records do if liveSolid(record) then for _,body in record.bodies do table.insert(out,body) end end end
 return out
end
-- Intersect the descending heading with live upper faces, just above contact.
-- Pick the first along the shot, rather than the highest object anywhere below.
-- Geometry behind/above the shot, steep walls and destroyed props do not qualify.
function Objects:projectileGround(origin,direction,range,radius,baseline)
 local ground,nearest=nil,math.huge
 if direction.Y>=-1e-7 then return nil end
 for _,record in self.records do
  if liveSolid(record) then
   for _,box in record.geometries do
   local plane=Geometry.planeHeight(box,origin.X,origin.Z)
   if plane then
    local slope=direction.Y+(box.up.X*direction.X+box.up.Z*direction.Z)/box.up.Y
    if slope< -1e-7 then
     local distance=(plane+(radius or 0)+.05-origin.Y)/slope
     if distance>=0 and distance<=range and distance<nearest then
      local point=origin+direction*distance
      local top=Geometry.support(box,point.X,point.Z,math.huge)
      if top and top>=baseline-.001 then ground=top;nearest=distance end
     end
    end
   end
  end
  end
 end
 return ground
end
function Objects:impact(hit,damage,projectile)
 local record=hit and self.byPart[hit.Instance]
 if not record or record.destroyed or not record.destructible or not finite(damage) or damage<=0 then return nil end
 if projectile and self.seen[projectile] then return nil end
 if projectile then self.seen[projectile]=true end
 local before=record.health
 record.health=math.max(0,before-damage); record.destroyed=record.health<=0
 if record.destroyed and record.regenerates then self.regenerating[record]=record.regenerationDelay end
 -- Turn off queries/blocking before the next projectile in the same server tick.
 self:sync(record)
 return record,before,record.health,record.destroyed
end
function Objects:stepRegeneration(dt,blocked)
 for record,remaining in self.regenerating do
  if not record.model.Parent then
   self.regenerating[record]=nil
  else
   remaining=math.max(0,remaining-dt)
   if remaining<=1e-6 and (not record.solid or not blocked or not blocked(record)) then
    self.regenerating[record]=nil
    record.health=record.maxHealth;record.destroyed=false
    self:sync(record)
   else
    self.regenerating[record]=remaining
   end
  end
 end
end
function Objects:trackEffect(part) table.insert(self.effects,part) end
function Objects:reset()
 table.clear(self.regenerating)
 for _,entry in self.moving do entry.clock=0;entry.spinClock=0;entry.spinAngle=0 end
 for _,part in self.effects do part:Destroy() end; table.clear(self.effects)
 for _,record in self.records do
  record.health=record.maxHealth; record.destroyed=record.destructible and record.health<=0; self:sync(record)
 end
 self:stepMotion(0)
 -- Keep weak projectile receipts: a completed projectile must not damage twice
 -- across reset. Entries vanish when the server releases the projectile record.
end
return Objects
