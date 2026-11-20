-- Arena ownership and temporary control leases. All methods run synchronously
-- through occupancy assignment: prompts/RPCs cannot yield into a second winner.
local Shared=game.ReplicatedStorage.Shared
local Config=require(Shared.BattleRoyaleConfig)
local BW=require(script.Parent.BWController)
local Components=require(Shared.VehicleComponents)
local Hardware=require(Shared.BWChassis)
local Motion=require(Shared.VehicleMotion)
local Effects=require(Shared.DamageEffects)
local Battle=require(script.Parent.LocalBattle)
local R={};R.__index=R
local function clearControl(tank,reason)
 BW.stop(tank,reason);BW.clearInputs(tank);tank.bw=nil;tank.autonomyActive=false
 tank.state.bwProgramKind=nil;tank.state.bwProgramName=nil
 tank.lastBWRequest=0;tank.bwRunRequestId=0
 local state=tank.state
 state.bwRunning=false;state.bwRequestId=0;state.bwRunRequestId=0
 state.bwStatus="stopped";state.bwMessage=reason;state.bwIndex=0;state.bwCount=0;state.bwLine=0;state.bwInstruction="";state.bwWarning="";state.bwSkipped=0
end
function R.new(options)
 local self=setmetatable({options=options,members={},slots={},battle={multiplayer=true}},R)
 for i=1,options.count do self.slots[i]={id="public:"..i,index=i,epoch=0,generation=-1};self:spawn(self.slots[i])end
 return self
end
function R:reading(member,message)
 local tank=member.tank
 return {requestId=member.lastRequest,revision=member.revision,selected=if tank then tank.id else nil,epoch=if tank then tank.state.controlEpoch else nil,generation=if tank then tank.state.generation else nil,controlMode=if tank then tank.state.controlMode else nil,personality=if tank then tank.state.personalityName else nil,mode=if not member.inBattle then "Menu" elseif tank then "Tank" else "OnFoot",message=message}
end
function R:notify(member,message)
 self.options.notify(member.player,self:reading(member,message))
end
function R:spawn(slot)
 local kind,assembly=slot.kind,slot.assembly
 if not kind then kind,assembly=Config.loadout(slot.index,if self.options.autonomy then math.random else nil);slot.kind=kind;slot.assembly=assembly end
 local tank=self.options.create(slot.id,kind,slot.index,assembly)
 if not tank then slot.retryAt=self.options.clock()+1;return end
 slot.retryAt=nil;slot.generation+=1;slot.epoch+=1;slot.tank=tank
 tank.id=slot.id;tank.public=true;tank.slot=slot;tank.owner=0
 tank.state.generation=slot.generation;tank.state.controlEpoch=slot.epoch;tank.state.public=true;tank.state.occupantUserId=nil
 tank.hitbox:SetAttribute("OwnerId",0);tank.hitbox:SetAttribute("OccupantUserId",nil)
 if self.options.autonomy then self.options.autonomy.attach(tank,slot.index);self.options.autonomy.start(tank,self.options.clock())end
 self:attachPrompt(tank)
end
function R:attachPrompt(tank)
 if tank.promptConnection then tank.promptConnection:Disconnect()end
 if tank.prompt then tank.prompt:Destroy()end
 local slot=tank.slot
 local prompt=Instance.new("ProximityPrompt");prompt.Name="EnterPublicTank";prompt.ActionText="Enter tank"
 prompt.ObjectText=(if tank.personality then tank.personality.name.." • "else "").."Bunny • "..(if tank.kind=="Boomer" then "Tracks" else "Wheels").." / "..(if tank.state.weaponId=="weapon.cannon" then "Cannon" else "Gatling")
 prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX
 prompt.MaxActivationDistance=Config.InteractionDistance;prompt.HoldDuration=.2;prompt.RequiresLineOfSight=false;prompt.Parent=tank.hitbox
 tank.prompt=prompt
 local epoch=tank.state.controlEpoch
 tank.promptConnection=prompt.Triggered:Connect(function(player)if slot.tank==tank and tank.prompt==prompt then self:enter(player,tank.id,epoch)end end)
end
function R:register(player)
 if self.members[player.UserId]then return end
 local member={player=player,inBattle=true,revision=1,lastRequest=0,lastAction=-math.huge};self.members[player.UserId]=member
 self.options.admit(player,member)
 local function added(character)
  if member.deathConnection then member.deathConnection:Disconnect();member.deathConnection=nil end
  if member.tank then self:release(member,"Character changed.")end
  task.spawn(function()
   local root=character:WaitForChild("HumanoidRootPart",10);local humanoid=character:WaitForChild("Humanoid",10)
   if self.members[player.UserId]~=member or player.Character~=character or not root or not humanoid then return end
   self.options.characters:restore(player,nil,false)
   if not member.inBattle then self:park(member)end
   member.deathConnection=humanoid.Died:Connect(function()if member.tank then self:release(member,"Character died.")end end)
  end)
 end
 member.characterConnection=player.CharacterAdded:Connect(added)
 if player.Character then added(player.Character)end
 self:notify(member)
end
function R:controlled(player,id,epoch)
 local member=self.members[player.UserId];local tank=member and member.tank
 if not member or not member.inBattle or not tank or type(id)~="string" or id~=tank.id or type(epoch)~="number" or epoch~=tank.state.controlEpoch or tank.occupant~=player.UserId or tank.state.health<=0 or tank.state.publicRetired then return nil end
 if not self.options.characters:alive(player)then return nil end
 return tank
end
function R:enter(player,id,epoch)
 local member=self.members[player.UserId]
 if not member or not member.inBattle or member.tank or type(id)~="string" then return false end
 local tank=self.options.tanks[id]
 if not tank or not tank.public or tank.occupant or tank.state.publicRetired or tank.state.health<=0 or epoch~=tank.state.controlEpoch then return false end
 local now=os.clock();if now-member.lastAction<Config.ActionInterval then return false end
 if not self.options.characters:alive(player)then return false end
 local root=self.options.characters:root(player)
 if (root.Position-(tank.state.position+Vector3.new(0,2.5,0))).Magnitude>Config.InteractionDistance then return false end
 member.lastAction=now;member.tank=tank;tank.occupant=player.UserId
 tank.slot.epoch+=1;tank.state.controlEpoch=tank.slot.epoch;tank.state.occupantUserId=player.UserId
 clearControl(tank,"Manual control.");tank.state.controlMode="Manual";tank.autoRestartAt=nil
 tank.prompt.Enabled=false;tank.hitbox:SetAttribute("OccupantUserId",player.UserId)
 local ok=pcall(self.options.characters.hide,self.options.characters,player,tank.state.position)
 if not ok then self:release(member,"Character unavailable.");return false end
 -- Successful entry grants new-tank HP, not a physical/weapon/spawn reset.
 tank.state.health=Components.get(tank.state).Chassis.Health
 tank.state.damageByWeapon={}
 if tank.effects then Effects.stop(tank.effects,tank.state)end
 Effects.severity(tank.state)
 member.revision+=1;self.options.select(player,tank,member);self:notify(member)
 return true
end
function R:release(member,reason,kill,silent,eject)
 local tank=member.tank;if not tank then return false end
 local ejection
 if eject then
  local components=Components.get(tank.state)
  local top=math.max(components.Chassis.HitboxHeight+components.Chassis.Hitbox.Y/2,components.Turret.MuzzleHeight+2)
  local velocity=Motion.ensure(tank.state)
  ejection={position=tank.state.position+Vector3.new(0,top+Config.EjectClearance,0),velocity=Vector3.new(velocity.X,Config.EjectSpeed,velocity.Z)}
 end
 clearControl(tank,reason)
 tank.hardware=nil;Components.withComputer(tank.state,"Bunny");tank.hardware=Hardware.forTank(tank.state);BW.applyHardware(tank)
 if tank.personality then self.options.autonomy.hardware(tank)end
 member.tank=nil;tank.occupant=nil;tank.slot.epoch+=1;tank.state.controlEpoch=tank.slot.epoch;tank.state.occupantUserId=nil
 tank.hitbox:SetAttribute("OccupantUserId",nil)
 if tank.state.health>0 and not tank.state.publicRetired then self:attachPrompt(tank)else tank.prompt.Enabled=false end
 member.revision+=1;self.options.select(member.player,nil,member)
 self.options.characters:restore(member.player,tank.state.position+Vector3.new(12,0,0),kill,ejection)
 if tank.personality and tank.state.health>0 and not tank.state.publicRetired then self.options.autonomy.start(tank,self.options.clock())end
 if not silent then self:notify(member,reason)end;return true
end
function R:park(member)
 local characters=self.options.characters
 if characters:alive(member.player)then
  local root=characters:root(member.player)
  characters:hide(member.player,root.Position-Vector3.new(0,3,0))
 end
end
function R:menu(member)
 if member.inBattle then
  if member.tank then self:release(member,"Returned to Main Menu.",false,true)end
  member.inBattle=false;member.revision+=1;self.options.depart(member.player);self:park(member)
 end
 self:notify(member)
 return true
end
function R:join(member)
 if not member.inBattle then
  local now=os.clock()
  if now-(member.lastJoin or -math.huge)<.5 then member.revision+=1;self:notify(member,"Please wait a moment before rejoining.");return false end
  member.lastJoin=now;member.inBattle=true;member.revision+=1
  self.options.admit(member.player,member)
  self.options.characters:restore(member.player,nil,false)
 end
 self:notify(member)
 return true
end
function R:request(player,action,requestId,id,epoch)
 local member=self.members[player.UserId]
 if not member or (action~="Sync" and action~="Enter" and action~="Exit" and action~="Menu" and action~="Join" and action~="Auto" and action~="Manual") or type(requestId)~="number" or requestId~=requestId or requestId%1~=0 or requestId<1 or requestId>1e9 or requestId<=member.lastRequest then return false end
 member.lastRequest=requestId
 if action=="Sync"then
  local now=os.clock();if now-(member.lastSync or -math.huge)<.5 then return false end;member.lastSync=now;self:notify(member);return true
 elseif action=="Auto"or action=="Manual"then
  local tank=self:controlled(player,id,epoch)
  if not tank or not tank.personality then return false end
  local now=os.clock();if now-member.lastAction<Config.ActionInterval then member.revision+=1;self:notify(member,"Please wait before switching control mode.");return false end
  member.lastAction=now
  clearControl(tank,"Control mode changed.")
  tank.slot.epoch+=1;tank.state.controlEpoch=tank.slot.epoch
  if action=="Auto"then self.options.autonomy.start(tank,self.options.clock())else tank.state.controlMode="Manual";tank.autoRestartAt=nil end
  member.revision+=1;self.options.select(player,tank,member);self:notify(member);return true
 elseif action=="Menu"then return self:menu(member)
 elseif action=="Join"then return self:join(member)
 elseif action=="Enter"then return self:enter(player,id,epoch)
 elseif self:controlled(player,id,epoch)then
  if self.options.safeExit and not self.options.safeExit(member.tank)then
   member.revision+=1;self:notify(member,"Cannot exit here: move onto safe ground away from the cliff edge.");return false
  end
  return self:release(member,"Exited tank.",false,false,true)
 end
 return false
end
function R:destroyed(tank)
 if tank.state.publicRetired then return end
 tank.state.publicRetired=true;clearControl(tank,"Tank destroyed.")
 Motion.setVelocity(tank.state,Vector3.zero)
 tank.state.angularVelocity=Vector3.zero;Motion.sync(tank.state)
 tank.prompt.Enabled=false;tank.retireAt=self.options.clock()+self.options.delay
 local member=tank.occupant and self.members[tank.occupant]
 if member then self:release(member,"Tank destroyed. Find another public tank.",true)end
end
function R:step()
 local now=self.options.clock()
 if self.options.hazard then
  for _,member in self.members do
   if member.inBattle and not member.tank and self.options.characters:alive(member.player)then
    local root,humanoid=self.options.characters:root(member.player)
    if self.options.hazard(root.Position)then humanoid.Health=0 end
   end
  end
 end
 for _,slot in self.slots do
  local tank=slot.tank
  if tank and tank.state.health>0 and self.options.hazard and self.options.hazard(tank.state.position)then
   Battle.environmentDamage(self.battle,tank)
  end
  if tank and self.options.autonomy then self.options.autonomy.step(tank,now)end
  if tank and tank.state.health<=0 then self:destroyed(tank)end
  if tank and tank.retireAt and now>=tank.retireAt then
   tank.promptConnection:Disconnect();self.options.remove(slot.id,tank);slot.tank=nil;self:spawn(slot)
  elseif not tank and slot.retryAt and now>=slot.retryAt then self:spawn(slot)end
 end
end
function R:remove(player)
 local member=self.members[player.UserId];if not member then return end
 if member.tank then self:release(member,"Occupant disconnected.",false,true)end
 if member.characterConnection then member.characterConnection:Disconnect()end
 if member.deathConnection then member.deathConnection:Disconnect()end
 self.options.characters:forget(player);self.members[player.UserId]=nil;self.options.depart(player)
end
return R
