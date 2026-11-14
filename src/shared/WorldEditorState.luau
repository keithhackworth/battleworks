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
 return setmetatable({document=copy(document),saved=copy(document),selection={},past={},future={},grid=1,snap=true,limit=100},State)
end
function State:dirty() return not equal(self.document,self.saved) end
function State:markSaved(document) self.document=copy(document or self.document); self.saved=copy(self.document) end
function State:snapshot() return {document=copy(self.document),selection=copy(self.selection)} end
function State:restore(snapshot) self.document=copy(snapshot.document); self.selection=copy(snapshot.selection) end
function State:record(before)
 if equal(before.document,self.document) then return false end
 table.insert(self.past,before); if #self.past>self.limit then table.remove(self.past,1) end
 table.clear(self.future); return true
end
function State:change(fn)
 local before=self:snapshot(); local ok,err=pcall(fn)
 if not ok then self:restore(before); error(err,0) end
 self:record(before)
end
function State:undo()
 local snapshot=table.remove(self.past); if not snapshot then return false end
 table.insert(self.future,self:snapshot()); self:restore(snapshot); return true
end
function State:redo()
 local snapshot=table.remove(self.future); if not snapshot then return false end
 table.insert(self.past,self:snapshot()); self:restore(snapshot); return true
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
function State:add(item,position,bounds)
 assert(#self.document.objects<512,"Object limit: 512")
 local id=self:nextId()
 self:change(function()
  table.insert(self.document.objects,{id=id,type=item.id,asset=item.model,position={self:snapValue(position[1]),0,self:snapValue(position[3])},rotation={0,0,0},scale=item.defaultScale or 1,solid=item.solid or false,destructible=item.destructible or false,hp=item.hp or 100,bounds=copy(bounds or item.size)})
  self.selection={[id]=true}
 end)
 return id
end
function State:delete()
 self:change(function()
  for id in self.selection do local _,spawn=self:find(id); assert(not spawn,"Tank spawns cannot be deleted; move them instead") end
  for i=#self.document.objects,1,-1 do if self.selection[self.document.objects[i].id] then table.remove(self.document.objects,i) end end
  self.selection={}
 end)
end
function State:duplicate()
 self:change(function()
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
