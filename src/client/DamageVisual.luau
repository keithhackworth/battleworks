-- Bounded local presentation of replicated injuries. No input/aim/physics mutation.
local Config=require(game.ReplicatedStorage.Shared.DamageEffectsConfig)
local Debris=game:GetService("Debris")
local Tween=game:GetService("TweenService")
local Smoke=require(script.Parent.SmokeVisual)
local Visual={}
local function sound(renderer,name,pitch,volume)
	local old=renderer[name]
	if old then old:Destroy() end
	local s=Instance.new("Sound"); s.Name=name; s.SoundId="rbxasset://sounds/"..(if name=="DamageClatter" then "electronicpingshort.wav" else "action_jump_land.mp3")
	s.Volume=volume; s.PlaybackSpeed=pitch; s.RollOffMaxDistance=100; s.Parent=renderer.chassis; s:Play()
	Debris:AddItem(s,1.5); renderer[name]=s
end
local function marks(renderer,state,part)
	local amount=(state.damageByWeapon or {}).Gatling or 0
	local count=math.min(Config.MaxBulletHoles,math.ceil(amount/5*(1+(state.rattleSeverity or 0)*0.6)))
	if state.health>50 then count=math.min(6,count) end
	if state.health<=0 and state.fatalWeapon=="Gatling" then count=Config.MaxBulletHoles end
	if count==0 and renderer.holesFolder then
		renderer.holesFolder:Destroy(); renderer.holesFolder=nil; renderer.holes={}
	end
	if count==0 then return end
	if not renderer.holesFolder then
		renderer.holesFolder=Instance.new("Folder"); renderer.holesFolder.Name="BulletHoles"; renderer.holesFolder.Parent=renderer.model; renderer.holes={}
	end
	for i=#renderer.holes+1,count do
		local host=if i%3==0 then renderer.turret else renderer.chassis
		local half=(host:GetAttribute("ArmorSize") or host.Size)*0.5
		local u=(i*37%101)/101*1.6-0.8; local v=(i*61%103)/103*1.5-0.75
		local face=i%5
		local offset
		if face==0 then offset=CFrame.new(u*half.X,half.Y+0.04,v*half.Z)*CFrame.Angles(0,0,math.pi/2)
		elseif face<=2 then offset=CFrame.new(u*half.X,v*half.Y,(if face==1 then -1 else 1)*(half.Z+0.04))*CFrame.Angles(0,math.pi/2,0)
		else offset=CFrame.new((if face==3 then -1 else 1)*(half.X+0.04),v*half.Y,u*half.Z) end
		local size=0.38+(i%3)*0.13
		local rim=part(renderer.holesFolder,"BulletScar",Vector3.new(0.065,(size+0.18)*Config.BulletHoleScale,(size+0.18)*Config.BulletHoleScale),Color3.fromRGB(153,155,158))
		rim.Shape=Enum.PartType.Cylinder
		local hole=part(renderer.holesFolder,"BulletHole",Vector3.new(0.08,size*Config.BulletHoleScale,size*Config.BulletHoleScale),Color3.fromRGB(12,14,16)); hole.Shape=Enum.PartType.Cylinder
		table.insert(renderer.holes,{host=host,offset=offset,rim=rim,hole=hole})
	end
end
function Visual.poseMarks(renderer)
	for _,mark in renderer.holes or {} do
		mark.rim.CFrame=mark.host.CFrame*mark.offset
		mark.hole.CFrame=mark.rim.CFrame
	end
end
function Visual.update(renderer,state,dt,part)
	renderer.damageClock=(renderer.damageClock or 0)+dt
	local time=renderer.damageClock
	marks(renderer,state,part)
	if state.health<=0 then
		Smoke.clear(renderer)
		if renderer.impactFolder then renderer.impactFolder:Destroy(); renderer.impactFolder=nil end
		for _,key in {"DamageClatter","EngineSputter"} do if renderer[key] then renderer[key]:Destroy(); renderer[key]=nil end end
		return
	end
	local severity=state.rattleSeverity or 0
	if severity>0 then
		local strength=severity/3*(if state.immobilized then 2 else 1)
		local shake=strength*Config.RattleVisualScale
		for i,item in renderer.details do
			local wheel=item.anchor:sub(1,5)=="wheel" or item.part.Name=="RoadWheel" or item.part.Name=="WheelHub" or item.part.Name=="TrackEnd"
			if item.anchor=="body" or item.anchor=="turret" or wheel then
				local noise=math.sin(time*67+i*1.7)*0.6+math.sin(time*97+i*0.9)*0.4
				item.part.CFrame=item.part.CFrame*CFrame.new(0,noise*0.1*shake,0)*CFrame.Angles(noise*0.045*shake,0,noise*0.055*shake)
			end
		end
		for i,tread in renderer.treads do
			tread.part.CFrame=tread.part.CFrame*CFrame.Angles(0,0,math.sin(time*81+i)*0.07*shake)
		end
		if time>=(renderer.nextClatter or 0) then
			sound(renderer,"DamageClatter",0.5+(state.rattleSerial or 0)%3*0.17,0.12+strength*0.35)
			renderer.nextClatter=time+0.65+(math.sin(time*37)+1)*0.35
		end
	end
	local smoke=state.smokeSeverity or 0
	Smoke.update(renderer,state,time,part)
	if smoke>0 and time>=(renderer.nextSputter or 0) then
		sound(renderer,"EngineSputter",0.7+smoke*0.2,0.13+smoke*0.06); renderer.nextSputter=time+2.3+(math.sin(time*13)+1)*0.6
	end
	local serial=state.damageSerial or 0
	if serial>(renderer.lastDamageSerial or serial) then
		local cannon=state.lastDamageWeapon=="Cannon"
		if not renderer.impactFolder then renderer.impactFolder=Instance.new("Folder"); renderer.impactFolder.Name="InjuryImpacts"; renderer.impactFolder.Parent=renderer.model end
		if cannon then
			Smoke.puff(renderer.impactFolder,state.lastDamagePosition or renderer.chassis.CFrame.Position,part,false)
		else
			local puff=part(renderer.impactFolder,"InjuryImpact",Vector3.new(1.5,1.5,1.5),Color3.fromRGB(255,221,99))
			puff.Shape=Enum.PartType.Ball; puff.Position=state.lastDamagePosition or renderer.chassis.CFrame.Position; puff.Material=Enum.Material.Neon
			Tween:Create(puff,TweenInfo.new(0.4),{Size=Vector3.new(3,3,3),Transparency=1}):Play(); Debris:AddItem(puff,0.45)
		end
	end
	renderer.lastDamageSerial=serial
end
return Visual
