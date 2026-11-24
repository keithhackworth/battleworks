local Shared=game.ReplicatedStorage.Shared
local Rules=require(Shared.WorldSound)
local Attachment=require(Shared.AssetAttachment)
local Visual=require(Shared.AssetGeometry)
local Catalog=require(Shared.CatalogData)
local Blocks={};Blocks.__index=Blocks
local Cell=32
local Tag="BattleWorksSoundBlock"
local function bounds(a,b,r)
 return math.floor((math.min(a.X,b.X)-r)/Cell),math.floor((math.max(a.X,b.X)+r)/Cell),
  math.floor((math.min(a.Z,b.Z)-r)/Cell),math.floor((math.max(a.Z,b.Z)+r)/Cell)
end
local function key(x,z) return x*1048576+z end
function Blocks.new(placements)
 local storage=game.ReplicatedStorage
 local list=storage.FindFirstChild and storage:FindFirstChild("BattleWorksSfxCatalog")
 local ids={}
 if list then
  local http=game:GetService("HttpService")
  local ok,entries=pcall(Catalog.decode,list,http)
  if ok and type(entries)=="table" then
   for _,item in entries do
    if type(item)=="table" and type(item.key)=="string" and type(item.assetId)=="string" and item.assetId:match("^[1-9]%d*$") and not string.find(string.lower(item.moderation or ""),"reject",1,true) then ids[item.key]=item.assetId end
   end
  end
 end
 return setmetatable({placements=placements,ids=ids,entries={},dynamic={},terrain={},grid={},large={},touched={},occupied={},serial=0,clock=0,query=0,assetTargets={},subjects={},useMoving=false,useTanks=false},Blocks)
end
function Blocks:index(block,a,b,padding)
 local minX,maxX,minZ,maxZ=bounds(a,b,block.radius+padding)
 if block.minX==minX and block.maxX==maxX and block.minZ==minZ and block.maxZ==maxZ then return end
 self:unindex(block)
 block.minX=minX;block.maxX=maxX;block.minZ=minZ;block.maxZ=maxZ
 block.large=(maxX-minX+1)*(maxZ-minZ+1)>128
 if block.large then self.large[block]=true;return end
 for x=minX,maxX do for z=minZ,maxZ do
  local id=key(x,z)
  local bucket=self.grid[id]
  if not bucket then bucket={};self.grid[id]=bucket end
  bucket[block]=true
 end end
end
function Blocks:unindex(block)
 if not block.minX then return end
 if block.large then self.large[block]=nil
 else
  for x=block.minX,block.maxX do for z=block.minZ,block.maxZ do
   local id=key(x,z);local bucket=self.grid[id]
   bucket[block]=nil;if not next(bucket) then self.grid[id]=nil end
  end end
 end
 block.minX=nil
end
function Blocks:add(model,spec)
 assert(spec.template==Rules.Asset,"Only Sound Blocks can emit world audio")
 Rules.validate(spec.sound)
 local part=model:FindFirstChildWhichIsA("BasePart",true)
 assert(part,"Sound Block has no volume")
 part.Transparency=1;part.CastShadow=false;part.CanQuery=false;part.CanTouch=false;part.CanCollide=false
 local id=self.ids[spec.sound.effect]
 self.placements[spec.id].soundPart=part
 self.placements[spec.id].attachment=spec.attachment
 local frame=part.CFrame
 local block={id=spec.id,part=part,model=model,config=spec.sound,attachment=spec.attachment,audible=id~=nil,
  relative=model:GetPivot():ToObjectSpace(frame),half=part.Size*.5,radius=part.Size.Magnitude*.5,
  frame=frame,previous=frame,occupants={},tracker={nextPlay=0,occupied=false},pulse=0,padding=0}
 self.entries[block]=true
 if spec.attachment or spec.motion or spec.spin then self.dynamic[block]=true end
 if id and spec.sound.activation~="Always" then
  local filter=spec.sound.filter
  if filter=="Terrain" then self.terrain[block]=true
  else self:index(block,frame.Position,frame.Position,0) end
  if filter=="Moving" or filter=="Both" then self.useMoving=true end
  if not filter or filter=="Tanks" or filter=="Both" then self.useTanks=true end
  if filter=="Specific" then for _,id in spec.sound.targets or {} do self.assetTargets[id]=true end end
 end
 block.destroying=part.Destroying:Connect(function() self:remove(block) end)
 if not id then return end
 if spec.sound.origin=="Trigger" then
  local source=Instance.new("ObjectValue");source.Name="SfxSource";source.Parent=part;block.source=source
 end
 for name,value in spec.sound do
  if name~="effect" and name~="targets" then part:SetAttribute("Sfx_"..name,value) end
 end
 part:SetAttribute("Sfx_AssetId",id)
 part:SetAttribute("Sfx_Active",spec.sound.activation=="Always")
 part:SetAttribute("Sfx_Pulse",0)
 part:AddTag(Tag)
end
function Blocks:remove(block)
 if block.destroying then block.destroying:Disconnect();block.destroying=nil end
 self:unindex(block)
 self.entries[block]=nil;self.dynamic[block]=nil
 self.terrain[block]=nil
 self.occupied[block]=nil;self.touched[block]=nil
end
function Blocks:poses()
 for block in self.dynamic do
  if not block.model.Parent then self:remove(block);continue end
  local placement=self.placements[block.id]
  local parent=block.attachment and self.placements[block.attachment.parent]
  local pivot=if placement.motion and placement.motion.frame then placement.motion.frame*placement.rest else placement.rest
  local padding=0
  if parent and parent.model.Parent then
   local parentPivot=parent.model:GetPivot()
   pivot=Attachment.follow(parentPivot,parent.rest or parentPivot,pivot)
   local previous=block.parentPivot
   if previous then
    local change=(previous.UpVector-parentPivot.UpVector).Magnitude+(previous.RightVector-parentPivot.RightVector).Magnitude
    padding=change*(block.frame.Position-previous.Position).Magnitude
   end
   block.parentPivot=parentPivot
  elseif block.attachment then
   -- A removed owner leaves the emitter at its last accepted world pose.
   pivot=block.model:GetPivot()
  end
  if block.attachment and block.model:GetPivot()~=pivot then block.model:PivotTo(pivot) end
  block.previous=block.frame;block.frame=pivot*block.relative;block.padding=padding
  if block.audible and not self.terrain[block] and block.config.activation~="Always" then self:index(block,block.previous.Position,block.frame.Position,padding) end
 end
end
local function candidate(block,body,kind)
 local id=body.id
 if not block[kind] or id<block[kind] then
  block[kind]=id;block[kind.."Source"]=body.soundSource
 end
end
function Blocks:observe(block,body)
 if block.query==self.query then return end
 block.query=self.query
 if not block.model.Parent then self:remove(block);return end
 if not Rules.accepts(block.config,block.attachment and block.attachment.parent,block.id,body.assetId or body.id,body.assetId~=nil,body.isMoving) then return end
 local start,finish=body.before.Position,body.after.Position
 local reach=block.radius+block.padding+body.radius
 local a,b=block.previous.Position,block.frame.Position
 if math.max(start.Y,finish.Y)+reach<math.min(a.Y,b.Y) or math.min(start.Y,finish.Y)-reach>math.max(a.Y,b.Y) then return end
 local inside,passed=Rules.overlap(block.previous,block.frame,block.half,body,block.padding+(body.padding or 0))
 local existing=block.occupants[body.id]
 if inside then
  if not existing then candidate(block,body,"entered");existing={source=body.soundSource};block.occupants[body.id]=existing end
  existing.seen=self.serial
 elseif passed and not existing then
  candidate(block,body,"entered");candidate(block,body,"exited")
 end
 if inside or passed then self.touched[block]=true end
end
function Blocks:queryBody(body)
 self.query+=1
 local minX,maxX,minZ,maxZ=bounds(body.before.Position,body.after.Position,body.radius+(body.padding or 0))
 if (maxX-minX+1)*(maxZ-minZ+1)>128 then
  for block in self.entries do if block.audible and block.config.activation~="Always" then self:observe(block,body) end end
 else
  for x=minX,maxX do for z=minZ,maxZ do
   local bucket=self.grid[key(x,z)]
   if bucket then for block in bucket do self:observe(block,body) end end
  end end
  for block in self.large do self:observe(block,body) end
 end
end
function Blocks:assetSubject(id,placement)
 if not placement then return end
 local model=placement.model
 if not model.Parent or (placement.record and placement.record.destroyed) then self.subjects[id]=nil;return end
 local pivot=model:GetPivot()
 local body=self.subjects[id]
 if not body then
  local part=placement.soundPart
  local frame,size
  if part then frame,size=part.CFrame,part.Size
  else
   local parts=Visual.parts(model)
   if #parts==0 then return end
   frame,size=Visual.measure(model);part=model.PrimaryPart or parts[1]
  end
  local parent=placement.attachment and self.placements[placement.attachment.parent]
  body={id="asset:"..id,assetId=id,isMoving=placement.motion~=nil or (parent~=nil and parent.motion~=nil),before=frame,after=frame,pivot=pivot,relative=pivot:ToObjectSpace(frame),
   halfX=size.X/2,halfZ=size.Z/2,bottom=-size.Y/2,top=size.Y/2,radius=size.Magnitude/2,
   soundSource=part}
  if placement.rest then body.after=placement.rest*body.relative end
  self.subjects[id]=body
 end
 local before=body.after
 body.before=before;body.after=pivot*body.relative
 local change=(body.pivot.UpVector-pivot.UpVector).Magnitude+(body.pivot.RightVector-pivot.RightVector).Magnitude
 body.padding=change*(before.Position-body.pivot.Position).Magnitude
 body.pivot=pivot
 self:queryBody(body)
end
function Blocks:observeTerrain(height)
 local id="terrain:"
 for block in self.terrain do
  if not block.model.Parent then self:remove(block);continue end
  local existing=block.occupants[id]
  local inside,passed=block.grounded,false
  if inside==nil or block.previous~=block.frame then
   inside,passed=Rules.terrainOverlap(block.previous,block.frame,block.half,height,existing~=nil,block.padding)
   block.grounded=inside
  end
  if inside then
   if not existing then existing={};block.occupants[id]=existing;block.entered=id end
   existing.seen=self.serial
  elseif passed and not existing then
   block.entered=id;block.exited=id
  end
  if inside or passed then self.touched[block]=true end
 end
end
function Blocks:step(bodies,dt,moving,groundHeight)
 self.clock+=dt;self.serial+=1;self:poses()
 if groundHeight then self:observeTerrain(groundHeight) end
 if not next(self.grid) and not next(self.large) and not next(self.occupied) and not next(self.touched) then return end
 if self.useTanks then for _,body in bodies do
  if body.state.health<=0 then continue end
  body.before,body.after=Rules.tankFrames(body)
  body.radius=math.sqrt(body.halfX^2+body.halfZ^2+((body.top-body.bottom)/2)^2)
  self:queryBody(body)
  body.before=nil;body.after=nil;body.radius=nil
 end end
 if self.useMoving then
  for _,entry in moving do
   if not self.assetTargets[entry.id] then self:assetSubject(entry.id,self.placements[entry.id]) end
  end
  for block in self.dynamic do
   local child=self.placements[block.id]
   local parent=block.attachment and self.placements[block.attachment.parent]
   if parent and parent.motion and child and not child.motion and not self.assetTargets[block.id] then self:assetSubject(block.id,child) end
  end
 end
 for id in self.assetTargets do
  local placement=self.placements[id]
  if placement then self:assetSubject(id,placement) end
 end
 for block in self.occupied do self.touched[block]=true end
 for block in self.touched do
  for id,contact in block.occupants do
   if contact.seen~=self.serial then
    block.occupants[id]=nil
    if not block.exited or id<block.exited then block.exited=id;block.exitedSource=contact.source end
   end
  end
  local occupied=next(block.occupants)~=nil
  self.occupied[block]=if occupied then true else nil
  local active,pulse=Rules.transition(block.config,block.tracker,block.entered~=nil,block.exited~=nil,occupied,self.clock)
  if active~=block.active then block.active=active;block.part:SetAttribute("Sfx_Active",active) end
  if pulse then
   if block.source then block.source.Value=if block.config.activation=="Exit" then block.exitedSource else block.enteredSource end
   block.pulse+=1;block.part:SetAttribute("Sfx_Pulse",block.pulse)
  end
  block.entered=nil;block.exited=nil;block.enteredSource=nil;block.exitedSource=nil
 end
 table.clear(self.touched)
end
function Blocks:reset()
 self.clock=0;table.clear(self.occupied);table.clear(self.touched);table.clear(self.subjects)
 for block in self.entries do
  table.clear(block.occupants);block.tracker.nextPlay=0;block.tracker.occupied=false;block.tracker.started=false
  block.entered=nil;block.exited=nil;block.enteredSource=nil;block.exitedSource=nil;block.active=nil;block.pulse=0;block.parentPivot=nil;block.grounded=nil
  if block.source then block.source.Value=nil end
  block.part:SetAttribute("Sfx_Active",block.config.activation=="Always")
  block.part:SetAttribute("Sfx_Pulse",0)
  block.part:SetAttribute("Sfx_Reset",(block.part:GetAttribute("Sfx_Reset") or 0)+1)
 end
 self:poses()
 for block in self.dynamic do block.previous=block.frame end
end
return Blocks
