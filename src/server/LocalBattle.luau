-- Lifecycle/ownership for a player's local two-tank test. Movement and weapons
-- remain in the same authoritative simulation used by manual and BW controls.
local Shared=game.ReplicatedStorage.Shared
local Simulation=require(Shared.TankSimulation)
local Effects=require(Shared.DamageEffects)
local Components=require(Shared.VehicleComponents)
local WorldSettings=require(Shared.WorldSettings)
local Weapon=require(Shared.RattlerWeapon)
local BW=require(script.Parent.BWController)
local Battle={}
function Battle.id(owner,kind)
	return if kind=="Boomer" then tostring(owner) else tostring(owner)..":Rattler"
end
function Battle.new(owner,index)
	return {owner=owner,index=index,selected=Battle.id(owner,"Boomer"),tanks={},winner=nil}
end
function Battle.pose(size,index,kind)
	local x=math.min(22,(size.X-10)/2)
	local z=math.clamp(size.Y*0.15-(index-1)*22,-size.Y/2+5,size.Y/2-5)
	return Vector3.new(if kind=="Boomer" then -x else x,0,z),if kind=="Boomer" then -math.pi/2 else math.pi/2
end
function Battle.resetTank(tank,size,index,reason)
	BW.stop(tank,reason)
 tank.bw=nil -- discard previous lifecycle command history and observation snapshots
	local generation=(tank.state and tank.state.generation or -1)+1
	local position,yaw=Battle.pose(size,index,tank.kind)
 if tank.worldSettings then position,yaw=WorldSettings.spawn(tank.worldSettings,tank.kind,index,if tank.worldObjects then tank.worldObjects:obstacles() else {}) end
	tank.spawn=position; tank.spawnYaw=yaw
	tank.state=Simulation.new(position,tank.kind,tank.seed,tank.assembly)
 tank.state.bwRunning=false; tank.state.bwStatus="stopped"; tank.state.bwMessage=reason or "Battle reset."
 tank.state.bwIndex=0; tank.state.bwCount=0; tank.state.bwLine=0; tank.state.bwInstruction=""
	tank.effects=Effects.new(tank.state)
	tank.sensorScanTimes=nil; tank.bwRunRequestId=0; tank.manualSensors=nil
	tank.state.yaw=yaw; tank.state.turretYaw=yaw; tank.state.generation=generation
	tank.rattler=Weapon.new(Components.get(tank.state).Weapon); tank.rattler.aimSeed=tank.seed
	tank.boomerAim={aimSeed=tank.seed}
	BW.applyHardware(tank); BW.clearInputs(tank); BW.sync(tank)
	tank.hitbox.CFrame=CFrame.new(position+Vector3.new(0,Components.get(tank.state).Chassis.HitboxHeight,0))*CFrame.Angles(0,yaw,0)
	local size=Components.get(tank.state).Chassis.Hitbox
 tank.hitbox.Size=Vector3.new(size.X,size.Y,size.Z)
	tank.hitbox.CanQuery=true
end
function Battle.select(battle,kind)
	local id=Battle.id(battle.owner,kind)
	if (kind~="Boomer" and kind~="Rattler") or not battle.tanks[id] or id==battle.selected then return false end
	local old=battle.tanks[battle.selected]
	if old and not BW.running(old) then BW.clearInputs(old) end
	battle.selected=id
	local nextTank=battle.tanks[id]
	if not BW.running(nextTank) then BW.clearInputs(nextTank) end
	return true
end
function Battle.damage(battle,victim,source,damage,weaponType,position)
	-- The local pair fights each other. Other players' pairs are separate tests.
	if not source or source==victim or source.owner~=victim.owner or victim.state.health<=0 then return false end
	if not victim.effects then victim.effects=Effects.new(victim.state) end
	local applied=math.min(victim.state.health,damage)
	victim.state.health=math.max(0,victim.state.health-applied)
	Effects.record(victim.effects,victim.state,weaponType or Components.get(source.state).Weapon.WeaponType,applied,position)
	if victim.state.health==0 then
		BW.stop(victim,"Tank destroyed."); BW.clearInputs(victim)
		victim.hitbox.CanQuery=false; victim.state.scanVisual=nil; victim.state.scanBW=nil; victim.state.scanManual=nil; victim.state.manualScannerActive=false
		battle.winner=if source.state.health>0 then source.kind else "Draw"
	end
	return true
end
return Battle
