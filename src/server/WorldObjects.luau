-- Imported scenery uses the same fixed-body solver and projectile hit stream as
-- arena cover. Native mesh physics stays disabled; trusted fitted proxy cells query.
local Contacts=require(game.ReplicatedStorage.Shared.VehicleContacts)
local Geometry=require(game.ReplicatedStorage.Shared.WorldObjectGeometry)
local Visual=require(game.ReplicatedStorage.Shared.AssetGeometry)
local Fit=require(script.Parent.MeshCollisionFit)
local Footprint=require(game.ReplicatedStorage.Shared.FootprintSupport)
local Objects={}; Objects.__index=Objects
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function Objects.new()
 return setmetatable({records={},byPart={},seen=setmetatable({},{__mode="k"}),effects={}},Objects)
end
function Objects:sync(record)
 local live=not record.destroyed
 for _,proxy in record.proxies do proxy.CanQuery=live and (record.solid or record.destructible) end
 for part,transparency in record.visuals do part.Transparency=if live then transparency else 1 end
 record.model:SetAttribute("WorldObjectId",record.id)
 record.model:SetAttribute("Health",record.health); record.model:SetAttribute("MaxHealth",record.maxHealth)
 record.model:SetAttribute("Destructible",record.destructible); record.model:SetAttribute("Destroyed",record.destroyed)
 record.model:SetAttribute("Solid",record.solid and live)
end
function Objects:add(model,spec)
 local v=spec.interaction
 if not v then return nil end
 assert(type(v.solid)=="boolean" and type(v.destructible)=="boolean" and finite(v.hp) and v.hp>=0,"Invalid world-object flags/health")
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
  Visual.checkFaceProfile(size,v)
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
 local record={id=spec.id,model=model,proxy=proxies[1],proxies=proxies,body=bodies[1],bodies=bodies,geometry=geometries[1],geometries=geometries,visuals=visuals,solid=v.solid,destructible=v.destructible,maxHealth=v.hp,health=v.hp,destroyed=v.destructible and v.hp<=0}
 for _,proxy in proxies do self.byPart[proxy]=record end
 self.records[record.id]=record
 self:sync(record); return record
end
function Objects:footprintSupport(position,yaw,shape)
 local boxes={}
 for _,record in self.records do
  if record.solid and not record.destroyed and record.proxy.Parent then
   for _,box in record.geometries do table.insert(boxes,box)end
  end
 end
 return Footprint.solve(boxes,position,yaw,shape)
end
function Objects:support(x,z,maxHeight)
 local height,surface
 for _,record in self.records do
  if record.solid and not record.destroyed and record.proxy.Parent then
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
 for _,record in self.records do if record.solid and not record.destroyed and record.proxy.Parent then for _,body in record.bodies do table.insert(out,body) end end end
 return out
end
-- Intersect the descending heading with live upper faces, just above contact.
-- Pick the first along the shot, rather than the highest object anywhere below.
-- Geometry behind/above the shot, steep walls and destroyed props do not qualify.
function Objects:projectileGround(origin,direction,range,radius,baseline)
 local ground,nearest=nil,math.huge
 if direction.Y>=-1e-7 then return nil end
 for _,record in self.records do
  if record.solid and not record.destroyed and record.proxy.Parent then
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
 -- Turn off queries/blocking before the next projectile in the same server tick.
 self:sync(record)
 return record,before,record.health,record.destroyed
end
function Objects:trackEffect(part) table.insert(self.effects,part) end
function Objects:reset()
 for _,part in self.effects do part:Destroy() end; table.clear(self.effects)
 for _,record in self.records do
  record.health=record.maxHealth; record.destroyed=record.destructible and record.health<=0; self:sync(record)
 end
 -- Keep weak projectile receipts: a completed projectile must not damage twice
 -- across reset. Entries vanish when the server releases the projectile record.
end
return Objects
