-- Imported scenery uses the same fixed-body solver and projectile hit stream as
-- arena cover. Native mesh physics stays disabled; only the trunk proxy queries.
local Contacts=require(game.ReplicatedStorage.Shared.VehicleContacts)
local Objects={}; Objects.__index=Objects
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function Objects.new()
 return setmetatable({records={},byPart={},seen=setmetatable({},{__mode="k"}),effects={}},Objects)
end
function Objects:sync(record)
 local live=not record.destroyed
 record.proxy.CanQuery=live and (record.solid or record.destructible)
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
 assert(math.abs(spec.rotation.X%360)<1e-5 and math.abs(spec.rotation.Z%360)<1e-5,"Interactive imported models must be upright")
 assert(not self.records[spec.id],"Duplicate world-object ID")
 local bounds,size=model:GetBoundingBox()
 local width,height,depth=size.X*v.fractions.X,size.Y*v.fractions.Y,size.Z*v.fractions.Z
 assert(width>0 and height>0 and depth>0,"Trunk collider has no volume")
 local visuals={}
 for _,part in model:GetDescendants() do if part:IsA("BasePart") then visuals[part]=part.Transparency or 0 end end
 local proxy=Instance.new("Part"); proxy.Name="WorldObstacleHitbox"
 proxy.Size=Vector3.new(width,height,depth)
 proxy.CFrame=CFrame.new(bounds.Position.X,spec.position.Y+height/2,bounds.Position.Z)*CFrame.Angles(0,math.rad(spec.rotation.Y),0)
 proxy.Shape=Enum.PartType.Block; proxy.Anchored=true; proxy.Transparency=1
 proxy.CanCollide=false; proxy.CanTouch=false; proxy.CanQuery=false
 proxy:SetAttribute("WorldObjectId",spec.id); proxy:SetAttribute("ScannerObjectName",model.Name or spec.id); proxy.Parent=model
 local record={id=spec.id,model=model,proxy=proxy,visuals=visuals,solid=v.solid,destructible=v.destructible,maxHealth=v.hp,health=v.hp,destroyed=v.destructible and v.hp<=0,
  body=Contacts.box("world:"..spec.id,proxy.CFrame.Position,proxy.Size.X/2,proxy.Size.Z/2,-proxy.Size.Y/2,proxy.Size.Y/2,math.rad(spec.rotation.Y))}
 self.records[record.id]=record; self.byPart[proxy]=record
 self:sync(record); return record
end
function Objects:obstacles()
 local out={}
 for _,record in self.records do if record.solid and not record.destroyed and record.proxy.Parent then table.insert(out,record.body) end end
 return out
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
