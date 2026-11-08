-- Pure server-driven injury/status state. Hits never extend an active episode.
local Config=require(script.Parent.DamageEffectsConfig)
local Effects={}
local function clearActive(state)
	state.smokeBurst=false; state.smokeRemaining=0
	state.immobilized=false; state.immobilizedRemaining=0
end
function Effects.new(state)
	state.damageByWeapon={}; state.damageSerial=0; state.fatalWeapon=nil; state.lastDamageWeapon=nil; state.lastDamagePosition=nil
	state.smokeSeverity=0; state.rattleSeverity=0; state.smokeStrength=0; state.rattleStrength=0
	state.smokeSerial=0; state.rattleSerial=0
	clearActive(state)
	return {clock=0,smoke={remaining=0,recovery=0,serial=0},rattle={remaining=0,recovery=0,serial=0}}
end
function Effects.severity(state)
	local band=0
	for index,hp in Config.Thresholds do if state.health<=hp then band=index end end
	local total,smoke,rattle=0,0,0
	for weapon,amount in state.damageByWeapon or {} do
		total+=amount
		local profile=Config.Weapons[weapon]
		if profile and profile.Effect=="smoke" then smoke+=amount elseif profile and profile.Effect=="rattle" then rattle+=amount end
	end
	state.smokeStrength=if total>0 then smoke/total else 0
	state.rattleStrength=if total>0 then rattle/total else 0
	state.smokeSeverity=band*state.smokeStrength; state.rattleSeverity=band*state.rattleStrength
	return band
end
function Effects.stop(effects,state)
	clearActive(state)
	state.smokeSeverity=0; state.rattleSeverity=0
	for _,key in {"smoke","rattle"} do effects[key].remaining=0; effects[key].recovery=0 end
end
function Effects.record(effects,state,weapon,amount,position)
	state.damageByWeapon=state.damageByWeapon or {}
	state.damageByWeapon[weapon]=(state.damageByWeapon[weapon] or 0)+amount
	state.damageSerial=(state.damageSerial or 0)+1; state.lastDamageWeapon=weapon; state.lastDamagePosition=position
	Effects.severity(state)
	if state.health<=0 then state.fatalWeapon=weapon; Effects.stop(effects,state) end
end
local function channel(effects,state,key,dt,band,tuning,strength)
	local c=effects[key]
	local activeField=if key=="smoke" then "smokeBurst" else "immobilized"
	local remainingField=if key=="smoke" then "smokeRemaining" else "immobilizedRemaining"
	if band==0 or strength<=0 then
		c.remaining=0; c.eligible=false
	elseif not c.eligible then
		c.eligible=true; c.recovery=tuning.FirstDelay
	end
	if c.remaining>0 then
		c.remaining=math.max(0,c.remaining-dt)
		if c.remaining==0 then
			-- Set recovery only on expiration, never on another hit. No overlapping stuns.
			c.recovery=math.max(tuning.MinRecovery,tuning.Recovery[band or 1] or tuning.MinRecovery)+(c.serial*0.618%1)*0.6
		end
	elseif band>0 and strength>0 then
		c.recovery=math.max(0,c.recovery-dt)
		if c.recovery==0 then
			c.serial+=1; c.remaining=tuning.Duration[band]*strength
		end
	end
	state[activeField]=c.remaining>0; state[remainingField]=c.remaining
	state[key.."Serial"]=c.serial
end
function Effects.step(effects,state,dt)
	if state.health<=0 then Effects.stop(effects,state); return end
	effects.clock+=dt
	local band=Effects.severity(state)
	channel(effects,state,"smoke",dt,band,Config.Smoke,state.smokeStrength)
	channel(effects,state,"rattle",dt,band,Config.Rattle,state.rattleStrength)
end
function Effects.input(state,command)
	if not state.immobilized then return command end
	local filtered=table.clone(command)
	filtered.throttle=0; filtered.steer=0
	return filtered -- aim/fire and simulated velocity/recoil are untouched
end
return Effects
