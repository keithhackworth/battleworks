-- Pure authoring state. No services, gameplay physics, filesystem or UI side effects.
local State={}; State.__index=State
local function copy(v)
 if type(v)~="table" then return v end
 local out={}; for k,n in v do out[k]=copy(n) end; return out
end
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in a do if not equal(v,b[k]) then return false end end
 for k in b do if a[k]==nil then return false end end
 return true
end
State.copy=copy
function State.new(document)
 return setmetatable({document=copy(document),saved=copy(document),selection={},pins={},past={},future={},grid=1,snap=true,limit=100},State)
end
State.equal=equal
function State:dirty() return not equal(self.document,self.saved) end
function State:markSaved(document) self.document=copy(document or self.document); self.saved=copy(self.document) end
function State:snapshot() return {document=copy(self.document),selection=copy(self.selection),pins=copy(self.pins)} end
function State:restore(snapshot) self.document=copy(snapshot.document); self.selection=copy(snapshot.selection);self.pins=copy(snapshot.pins or {}) end
function State:record(before)
 if equal(before.document,self.document) then return false end
 table.insert(self.past,{document=copy(before.document),pins=copy(before.pins or {})}); if #self.past>self.limit then table.remove(self.past,1) end
 table.clear(self.future); return true
end
function State:change(fn)
 local before=self:snapshot(); local ok,err=pcall(fn)
 if not ok then self:restore(before); error(err,0) end
 self:record(before)
end
function State:restoreHistory(snapshot)
 self.document=copy(snapshot.document);self.pins=copy(snapshot.pins or {})
 -- Keep the user's present selection; history never selects an old object.
 for id in self.selection do if not self:find(id) then self.selection[id]=nil end end
end
local function historySnapshot(state)return {document=copy(state.document),pins=copy(state.pins)}end
function State:undo()
 local snapshot=table.remove(self.past); if not snapshot then return false end
 table.insert(self.future,historySnapshot(self)); self:restoreHistory(snapshot); return true
end
function State:redo()
 local snapshot=table.remove(self.future); if not snapshot then return false end
 table.insert(self.past,historySnapshot(self)); self:restoreHistory(snapshot); return true
end
function State:find(id)
 for _,entry in self.document.objects do if entry.id==id then return entry,false end end
 for _,entry in self.document.spawns do if entry.id==id then return entry,true end end
end
function State:select(id,extend)
 if not extend then self.selection={} end
 if id and self:find(id) then self.selection[id]=not (extend and self.selection[id]) or nil end
end
function State:snapValue(value) return if self.snap then math.round(value/self.grid)*self.grid else value end
function State:nextId()
 local n=1; while self:find("object_"..n) do n+=1 end; return "object_"..n
end
function State:add(item,position,bounds,scale)
 assert(#self.document.objects<512,"Object limit: 512")
 local id=self:nextId()
 self:change(function()
  table.insert(self.document.objects,{id=id,type=item.id,asset=item.model,position={self:snapValue(position[1]),0,self:snapValue(position[3])},rotation={0,0,0},scale=scale or item.defaultScale or 1,solid=item.solid or false,destructible=item.destructible or false,hp=item.hp or 100,bounds=copy(bounds or item.size)})
  self.selection={[id]=true}
 end)
 return id
end
function State:addStart(position)
 local used={};for _,p in self.document.spawns do used[p.slot]=true end
 local slot=1;while used[slot] do slot+=1 end
 assert(slot<=5,"All five starting positions are placed; move or delete an existing area")
 local id="start_"..slot;local suffix=1
 while self:find(id) do suffix+=1;id="start_"..slot.."_"..suffix end
 self:change(function()
  table.insert(self.document.spawns,{id=id,slot=slot,position={self:snapValue(position.X),0,self:snapValue(position.Z)},heading=0})
  self.selection={[id]=true}
 end)
 return id
end
function State:delete()
 self:change(function()
  for id in self.selection do local p,spawn=self:find(id);assert(not spawn or p.slot,"Legacy tank spawns cannot be deleted") end
  for i=#self.document.spawns,1,-1 do if self.selection[self.document.spawns[i].id] then table.remove(self.document.spawns,i) end end
  for i=#self.document.objects,1,-1 do if self.selection[self.document.objects[i].id] then self.pins[self.document.objects[i].id]=nil;table.remove(self.document.objects,i) end end
  self.selection={}
 end)
end
function State:duplicate()
 self:change(function()
  for id in self.selection do local p,spawn=self:find(id);assert(not spawn,"Use Place tank start to add the next numbered area") end
  local originals={}; for _,o in self.document.objects do if self.selection[o.id] then table.insert(originals,copy(o)) end end
  assert(#self.document.objects+#originals<=512,"Object limit: 512")
  self.selection={}
  for _,o in originals do o.id=self:nextId(); o.position[1]+=self.grid; table.insert(self.document.objects,o); self.selection[o.id]=true end
 end)
end
function State:move(dx,dz)
 self:change(function() for id in self.selection do local o=self:find(id); if o then o.position[1]=self:snapValue(o.position[1]+dx); o.position[3]=self:snapValue(o.position[3]+dz) end end end)
end
function State:rotate(degrees)
 self:change(function() for id in self.selection do local o,spawn=self:find(id); if o then if spawn then o.heading=(o.heading+degrees)%360 else o.rotation[2]=(o.rotation[2]+degrees)%360 end end end end)
end
function State:scale(factor)
 assert(type(factor)=="number" and factor>0 and factor<1000,"Invalid scale factor")
 self:change(function() for id in self.selection do local o,spawn=self:find(id); if o and not spawn then o.scale=math.clamp(o.scale*factor,.001,1000) end end end)
end
return State
