-- Private per-user slots. UpdateAsync protects existing revisions across servers.
local Store={};Store.__index=Store
function Store.new(dataStore,temporary,encode)
 return setmetatable({dataStore=dataStore,temporary=temporary,encode=encode,memory={}},Store)
end
local function validId(id) return type(id)=="string" and #id<=64 and id:match("^[a-zA-Z][a-zA-Z0-9_-]*$")~=nil end
function Store:read(owner)
 if self.temporary then return self.memory[owner] or {worlds={}} end
 return self.dataStore:GetAsync("player:"..owner) or {worlds={}}
end
function Store:list(owner)
 local result={}
 for id,entry in self:read(owner).worlds do table.insert(result,{id=id,name=entry.document.name,revision=entry.revision}) end
 table.sort(result,function(a,b) return a.id<b.id end)
 return result
end
function Store:load(owner,id)
 assert(validId(id),"Invalid saved world ID")
 return assert(self:read(owner).worlds[id],"Saved world not found")
end
function Store:save(owner,document,expected)
 assert(validId(document.id) and type(expected)=="number" and expected%1==0 and expected>=0,"Invalid save revision")
 local entry
 local function update(profile)
  profile=profile or {worlds={}}
  local worlds=table.clone(profile.worlds)
  local old=worlds[document.id]
  assert((if old then old.revision else 0)==expected,"World changed elsewhere. Open it again, or save with a new World ID.")
  local count=0;for _ in worlds do count+=1 end
  assert(old or count<10,"You can save up to 10 worlds. Reuse a World ID to update it.")
  entry={document=document,revision=expected+1};worlds[document.id]=entry
  local nextProfile={worlds=worlds}
  assert(#self.encode(nextProfile)<=3000000,"Saved worlds exceed the storage limit")
  return nextProfile
 end
 if self.temporary then self.memory[owner]=update(self.memory[owner]) else self.dataStore:UpdateAsync("player:"..owner,update) end
 return entry
end
function Store:forget(owner) if self.temporary then self.memory[owner]=nil end end
return Store
