-- Cache part membership only. Queries and scanner probes use live Instances.
local profileBegin=debug.profilebegin or function()end
local profileEnd=debug.profileend or function()end
local Scene={}
Scene.__index=Scene

function Scene.new(arena,world,floor,tanks,targets)
 local self=setmetatable({
  arena=arena,world=world,floor=floor,tanks=tanks,targets=targets,dirty=true,
  geometry={},terrain={},records={},watched={},included={},dynamic=setmetatable({},{__mode="k"}),
 },Scene)
 arena.DescendantAdded:Connect(function(part)
  if self:watch(part) and part.CanQuery~=false then self:invalidate() end
 end)
 arena.DescendantRemoving:Connect(function(part)
  local connections=self.watched[part]
  if not connections then return end
  self.watched[part]=nil
  connections.query:Disconnect()
  connections.terrain:Disconnect()
  if self.included[part] then self:invalidate() end
 end)
 return self
end

function Scene:invalidate() self.dirty=true end

function Scene:markDynamic(part)
 -- Register before parenting. Tank hitboxes and destructible practice targets
 -- are collected live, including changes during the same simulation tick.
 self.dynamic[part]=true
end

function Scene:watch(part)
 if part==self.floor or self.dynamic[part] or not (part:IsA("BasePart") or part:IsA("Part")) then return false end
 if not self.watched[part] then
  self.watched[part]={
   query=part:GetPropertyChangedSignal("CanQuery"):Connect(function()
    if (part.CanQuery~=false)~=(self.included[part]==true) then self:invalidate() end
   end),
   terrain=part:GetAttributeChangedSignal("ScannerTerrainOnly"):Connect(function()
    if part.CanQuery~=false then self:invalidate() end
   end),
  }
 end
 return true
end

local function collect(scene,part)
 if part.CanQuery==false then return end
 local parent=part.Parent
 if not parent or (parent~=scene.arena and not part:IsDescendantOf(scene.arena)) then return end
 if part:GetAttribute("ScannerTerrainOnly")~=true then table.insert(scene.geometry,part) end
 table.insert(scene.terrain,part)
end

function Scene:rebuild()
 profileBegin("BattleWorks.ScannerScene")
 table.clear(self.geometry);table.clear(self.terrain);table.clear(self.included)
 for _,part in self.arena:GetDescendants() do
  if self:watch(part) and part.CanQuery~=false then
   if part:GetAttribute("ScannerTerrainOnly")==true then table.insert(self.terrain,part)
   else table.insert(self.geometry,part) end
   self.included[part]=true
  end
 end
 for _,part in self.geometry do table.insert(self.terrain,part) end
 self.geometryCount=#self.geometry
 self.terrainCount=#self.terrain
 self.dirty=false
 profileEnd()
end

function Scene:read()
 if self.dirty then self:rebuild() end
 -- Reuse the cached arrays and replace only their dynamic tails.
 for i=#self.geometry,self.geometryCount+1,-1 do self.geometry[i]=nil end
 for i=#self.terrain,self.terrainCount+1,-1 do self.terrain[i]=nil end
 table.clear(self.records)
 for id,tank in self.tanks do
  local hitbox=tank.hitbox
  self.records[hitbox]={state=tank.state,id=id,playerName=tank.playerName,tankName=tank.tankName or tank.kind,teamId=tank.teamId}
  collect(self,hitbox)
 end
 for target in self.targets do collect(self,target) end
 if self.floor.CanQuery then table.insert(self.terrain,self.floor) end
 local native=self.world:FindFirstChild("Terrain")
 if native then table.insert(self.terrain,native) end
 return self.geometry,self.records,self.terrain
end

return Scene
