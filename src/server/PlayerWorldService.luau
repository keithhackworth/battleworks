-- Owns persistence and launch orchestration, never gameplay simulation.
local Adapter=require(script.Parent.PlayerWorldDocument)
local Store=require(script.Parent.PlayerWorldStore)
local Service={};Service.__index=Service
function Service.new(options)
 local self=setmetatable(options,Service)
 self.store=Store.new(options.dataStore,options.studio,function(v) return options.http:JSONEncode(v) end)
 self.requests={};self.pending={};self.ready={}
 return self
end
function Service:register(player)
 if self.studio or not self.reserved then return end
 local ok,join=pcall(function() return player:GetJoinData() end)
 local data=ok and join and join.TeleportData
 if join and join.SourcePlaceId==self.placeId and type(data)=="table" and data.battleWorksWorld==true and data.owner==player.UserId
  and type(data.id)=="string" and type(data.revision)=="number" then
  self.pending[player.UserId]=data
 end
end
function Service:canEnter(player)
 return not self.reserved or self.ready[player.UserId]==true
end
function Service:validate(document)
 assert(type(document)=="table" and #self.http:JSONEncode(document)<=260000,"World exceeds 260 KB")
 return Adapter.validate(document,self.items,self.assets)
end
function Service:request(player,action,payload)
 local owner=player.UserId
 local allowed={List=true,Load=true,Save=true,Play=true,Bootstrap=true}
 if type(action)~="string" or not allowed[action] then return {ok=false,message="Unknown world action"} end
 local state=self.requests[owner] or {last={}};self.requests[owner]=state
 if state.busy or os.clock()-(state.last[action] or -math.huge)<.8 then return {ok=false,message="Please wait a moment and try again."} end
 state.busy=true;state.last[action]=os.clock()
 local ok,result=pcall(function()
  assert(self.isPresent(player),"Player left the experience")
  if action=="List" then return {worlds=self.store:list(owner)} end
  if action=="Load" then return self.store:load(owner,payload) end
  if action=="Save" then
   assert(type(payload)=="table","Missing world")
   local document=self:validate(payload.document)
   return self.store:save(owner,document,payload.revision)
  end
  if action=="Bootstrap" then
   local launch=self.pending[owner]
   if not launch then return {launch=false} end
   local entry=self.store:load(owner,launch.id)
   assert(entry.revision==launch.revision,"Saved world changed before launch. Open it and play again.")
   local document,specs,settings=self:validate(entry.document)
   assert(self.isPresent(player),"Player left the experience")
   self.install(player,document,specs,settings)
   self.pending[owner]=nil;self.ready[owner]=true
   return {launch=true}
  end
  assert(not self.inBattle(player),"Return to the menu before playing a saved world")
  assert(type(payload)=="table","Missing saved world")
  local entry=self.store:load(owner,payload.id)
  assert(entry.revision==payload.revision,"Open the latest saved revision before playing")
  local document,specs,settings=self:validate(entry.document)
  assert(self.isPresent(player),"Player left the experience")
  if self.studio then
   self.install(player,document,specs,settings)
   return {launch=true}
  end
  self.teleport(player,{battleWorksWorld=true,owner=owner,id=document.id,revision=entry.revision})
  return {teleporting=true}
 end)
 state.busy=false
 if not ok then return {ok=false,message=tostring(result):gsub("^.-:%d+:%s*","")} end
 local response=table.clone(result);response.ok=true;response.temporary=self.studio
 return response
end
function Service:remove(player)
 local owner=player.UserId
 self.requests[owner]=nil;self.pending[owner]=nil;self.ready[owner]=nil;self.store:forget(owner)
end
return Service
