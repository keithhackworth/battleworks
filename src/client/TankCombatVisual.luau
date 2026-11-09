-- Presentation only: health and death are authoritative snapshot values.
local Debris=game:GetService("Debris")
local Tween=game:GetService("TweenService")
local DamageConfig=require(game.ReplicatedStorage.Shared.DamageEffectsConfig)
local Smoke=require(script.Parent.SmokeVisual)
local Visual={}
function Visual.attach(renderer)
	local gui=Instance.new("BillboardGui"); gui.Name="TankHealth"
	gui.Size=UDim2.fromOffset(190,44); gui.StudsOffset=Vector3.new(0,10,0)
	gui.AlwaysOnTop=true; gui.MaxDistance=500; gui.Adornee=renderer.chassis; gui.Parent=renderer.chassis
	local label=Instance.new("TextLabel"); label.Size=UDim2.new(1,0,0,26)
	label.BackgroundColor3=Color3.fromRGB(24,31,35); label.BackgroundTransparency=0.65
	label.TextColor3=Color3.fromRGB(255,249,222); label.Font=Enum.Font.GothamBold; label.TextSize=14; label.Parent=gui
	local track=Instance.new("Frame"); track.Position=UDim2.fromOffset(0,28); track.Size=UDim2.new(1,0,0,12)
	track.BorderSizePixel=0; track.BackgroundTransparency=0.65; track.BackgroundColor3=Color3.fromRGB(55,35,35); track.Parent=gui
	local bar=Instance.new("Frame"); bar.Size=UDim2.fromScale(1,1); bar.BackgroundTransparency=0.25; bar.BorderSizePixel=0; bar.Parent=track
	renderer.healthLabel=label; renderer.healthBar=bar
end
local function isPart(p) return p:IsA("BasePart") or p:IsA("Part") end
local function explosion(renderer,state,part)
	local effects=Instance.new("Folder"); effects.Name="DestructionEffects"; effects.Parent=renderer.model
	Debris:AddItem(effects,2.5)
	local center=state.position+Vector3.new(0,3,0)
	local flash=part(effects,"TankFireball",Vector3.new(8,8,8),Color3.fromRGB(255,239,155))
	flash.Shape=Enum.PartType.Ball; flash.Material=Enum.Material.Neon; flash.Position=center
	local thud=Instance.new("Sound"); thud.Name="DestructionBoom"
	thud.SoundId="rbxasset://sounds/action_jump_land.mp3"; thud.Volume=1.5; thud.PlaybackSpeed=0.4
	thud.RollOffMaxDistance=200; thud.Parent=flash; thud:Play()
	Tween:Create(flash,TweenInfo.new(0.45,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{
		Size=Vector3.new(24,24,24),Transparency=1}):Play()
	local wave=part(effects,"TankShockwave",Vector3.new(0.2,5,5),Color3.fromRGB(255,196,70))
	wave.Shape=Enum.PartType.Cylinder; wave.Material=Enum.Material.Neon
	wave.CFrame=CFrame.new(state.position+Vector3.new(0,0.25,0))*CFrame.Angles(0,0,math.pi/2)
	Tween:Create(wave,TweenInfo.new(0.55,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{
		Size=Vector3.new(0.1,40,40),Transparency=1}):Play()
	Smoke.puff(effects,center,part,true)
	for index=1,16 do
		local angle=index*math.pi*2/16
		local radial=Vector3.new(math.cos(angle),0,math.sin(angle))
		local puff=part(effects,"TankDestruction",Vector3.new(5,5,5),if index%2==0 then Color3.fromRGB(255,110,18) else Color3.fromRGB(255,213,47))
		puff.Shape=Enum.PartType.Ball; puff.Position=center+radial*2; puff.Material=Enum.Material.Neon
		Tween:Create(puff,TweenInfo.new(0.7,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{
			Size=Vector3.new(9,9,9),Position=center+radial*13+Vector3.new(0,index%3*3,0),Transparency=1}):Play()
	end
end
local function beginWreck(renderer,state,anchors,animate)
	local profile=DamageConfig.Weapons[state.fatalWeapon]
	local collapse=profile and profile.Destruction=="Collapse"
	local death={age=if animate then 0 else 10,groups={},colors={},body={},collapse=collapse,clinked=not animate}
	local groups,detached={},{}
	for _,p in renderer.model:GetChildren() do
		if isPart(p) then
			death.colors[p]=p.Color
			local dark=p.Name:find("Track") or p.Name:find("Tire") or p.Name:find("Bore")
			p.Color=if dark then Color3.fromRGB(51,53,56) else Color3.fromRGB(117,120,124)
		end
	end
	local function add(key,center,p)
		local group=groups[key]
		if not group then
			local index=#death.groups+1
			local turret=key=="turret"
			local angle=index*2.4
			local horizontal=if collapse then 3 else (if turret then 8 else 12)
			group={parts={},center=center,ground=state.position.Y-(state.lift or 0)+(if turret then 1.5 else 1),
				velocity=Vector3.new(math.cos(angle)*horizontal,if collapse then 2+index%3 else (if turret then 54 else 18+index%3*3),math.sin(angle)*horizontal),
				spin=Vector3.new(if collapse then 2 else (if turret then 2.8 else 5),1.2,index%2*4-2)}
			groups[key]=group; table.insert(death.groups,group)
		end
		table.insert(group.parts,{part=p,frame=p.CFrame}); detached[p]=true
	end
	local function track(side,p)
		add("track"..side,(anchors.base*CFrame.new(side*3.8,1.4,0)).Position,p)
	end
	for _,item in renderer.details do
		if item.anchor=="turret" or item.anchor=="barrel" or item.anchor=="rotor" then
			add("turret",anchors.turret.Position,item.part)
		elseif item.anchor:sub(1,5)=="wheel" then
			add(item.anchor,anchors[item.anchor].Position,item.part)
		elseif renderer.tankType=="Boomer" then
			if item.part.Name=="RoadWheel" or item.part.Name=="WheelHub" or item.part.Name=="Axle" then
				local key="wheel"..(if item.offset.Position.X<0 then "L" else "R")..tostring(item.offset.Position.Z)
				add(key,item.part.CFrame.Position,item.part)
			elseif item.part.Name=="TrackEnd" then track(if item.offset.Position.X<0 then -1 else 1,item.part) end
		end
	end
	if renderer.tankType=="Boomer" then
		track(-1,renderer.left); track(1,renderer.right)
		for _,tread in renderer.treads do track(tread.side,tread.part) end
	end
	for _,p in renderer.model:GetChildren() do if isPart(p) and not detached[p] then table.insert(death.body,p) end end
	renderer.death=death
end
local function animateWreck(renderer,dt)
	local death=renderer.death; death.age+=math.max(0,dt)
	local collapse=death.collapse
	local age=math.max(0,death.age-(if collapse then 0.35 else 0))
	if collapse then
		local shake=math.max(0,1-death.age/0.5)*(math.sin(death.age*137)+math.sin(death.age*91))*0.06
		for _,p in death.body do p.CFrame=p.CFrame*CFrame.new(0,-math.min(1,age/0.6)*1.15,0)*CFrame.Angles(shake,0,-shake) end
		if not death.clinked and death.age>=1.3 then
			death.clinked=true
			local clink=Instance.new("Sound"); clink.Name="FinalClink"; clink.SoundId="rbxasset://sounds/electronicpingshort.wav"
			clink.Volume=0.7; clink.PlaybackSpeed=0.5; clink.RollOffMaxDistance=120; clink.Parent=renderer.chassis; clink:Play(); Debris:AddItem(clink,1.5)
		end
	end
	for _,group in death.groups do
		local g=85
		local above=math.max(0,group.center.Y-group.ground)
		local land=(group.velocity.Y+math.sqrt(group.velocity.Y^2+2*g*above))/g
		local t=math.min(age,land)
		local after=math.max(0,age-land)
		local horizontal=t+(1-math.exp(-after*6))/6
		local y=if after>0 then group.ground+math.abs(math.sin(math.min(after,0.6)*math.pi/0.6))*math.exp(-after*5)*0.8
			else group.center.Y+group.velocity.Y*t-0.5*g*t*t
		local center=Vector3.new(group.center.X+group.velocity.X*horizontal,y,group.center.Z+group.velocity.Z*horizontal)
		local spin=group.spin*(t+math.min(after,0.4)*0.3)
		local jolt=if collapse then math.max(0,1-death.age/0.4)*math.sin(death.age*157)*0.09 else 0
		local transform=CFrame.new(center)*CFrame.Angles(spin.X+jolt,spin.Y,spin.Z-jolt)*CFrame.new(-group.center.X,-group.center.Y,-group.center.Z)
		for _,item in group.parts do item.part.CFrame=transform*item.frame end
	end
end
function Visual.update(renderer,state,part,anchors,dt)
	local maximum=state.maxHealth or 100
	local hp=math.clamp(state.health,0,maximum)
	renderer.healthLabel.Text=string.format("%s  %d/%d%s",if renderer.tankType=="Boomer" then "Bullet Boomer" else "Rattler",hp,maximum,if hp==0 then " • KO" else "")
	renderer.healthBar.Size=UDim2.fromScale(hp/maximum,1)
	renderer.healthBar.BackgroundColor3=if hp/maximum>0.3 then Color3.fromRGB(99,218,77) else Color3.fromRGB(244,69,37)
	if hp==0 then
		if not renderer.death then
			local animate=(renderer.lastHealth or 0)>0
			beginWreck(renderer,state,anchors,animate)
			if animate and not renderer.death.collapse then explosion(renderer,state,part) end
		end
		animateWreck(renderer,dt)
		-- The grey wreck stays solid/readable; the firing-only swell stays hidden.
		for _,p in renderer.model:GetChildren() do if isPart(p) then p.Transparency=0 end end
		for _,p in {renderer.barrelBulge,renderer.muzzleSwell,renderer.coughBore} do if p then p.Transparency=1 end end
	elseif renderer.death then
		for p,color in renderer.death.colors do p.Color=color end
		renderer.death=nil
	end
	renderer.lastHealth=hp
end
return Visual
