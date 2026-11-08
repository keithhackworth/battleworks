-- Decorations use completed server observations: explicit BW or driver-only sweep.
local Config=require(game.ReplicatedStorage.Shared.ScannerConfig)
local Geometry=require(game.ReplicatedStorage.Shared.ScannerGeometry)
local Visual={}
function Visual.build(renderer,detail)
	renderer.scannerSensors={}
	local radius=if renderer.tankType=="Rattler" then 3.8 else 4.2
	for i=1,Config.SensorCount do
		local angle=(i-1)*math.pi*2/Config.SensorCount
		local frame=CFrame.new(math.sin(angle)*radius,1.2,-math.cos(angle)*radius)
		local armRadius=(radius+2.6)/2
		detail("ScannerArm",Vector3.new(0.22,0.22,radius-2.6),Color3.fromRGB(85,94,104),"body",
			CFrame.new(math.sin(angle)*armRadius,0.75,-math.cos(angle)*armRadius)*CFrame.Angles(0,-angle,0))
		detail("ScannerStem",Vector3.new(0.6,0.18,0.18),Color3.fromRGB(85,94,104),"body",frame*CFrame.new(0,-0.25,0)*CFrame.Angles(0,0,math.pi/2),Enum.PartType.Cylinder)
		detail("ScannerSocket",Vector3.new(1.3,0.22,1.3),Color3.fromRGB(45,52,61),"body",frame,Enum.PartType.Ball)
		local lens=detail("ScannerSensor",Vector3.one*Config.LensSize,Color3.fromRGB(77,120,136),"body",frame*CFrame.new(0,0.55,0),Enum.PartType.Ball)
		table.insert(renderer.scannerSensors,lens)
	end
end
local function priority(event)
	return if event.kind=="tank" then (if event.affiliation=="enemy" then 4 else 3) elseif event.kind=="wall" then 2 else 1
end
function Visual.update(renderer,state,dt)
	renderer.sensorClock=(renderer.sensorClock or 0)+dt
	if state.health<=0 then
		renderer.sensorReadings={}
		for _,lens in renderer.scannerSensors do lens.Material=Enum.Material.SmoothPlastic; lens.Size=Vector3.one*Config.LensSize end
		return
	end
	local readings=renderer.sensorReadings or {}; renderer.sensorReadings=readings
	local seen={}
	local function observe(event)
		if not event then return end
		seen[event.serial]=true
		local cached=readings[event.serial]
		if not cached then cached={event=event,remaining=event.remaining}; readings[event.serial]=cached end
		cached.remaining=math.max(0,math.min(cached.remaining,event.remaining)-dt)
	end
	observe(state.scanVisual)
	if state.manualScannerActive then for _,event in state.scanManual or {} do observe(event) end end
	local selected={}
	for serial,cached in readings do
		if not seen[serial] then readings[serial]=nil; continue end
		if cached.remaining<=0 then continue end
		local event=cached.event
		local index=Geometry.sensorIndex(event.angle)
		local previous=selected[index]
		if not previous or priority(event)>priority(previous.event) or (priority(event)==priority(previous.event) and event.proximity>=previous.event.proximity) then selected[index]=cached end
	end
	for i,lens in renderer.scannerSensors do
		local cached=selected[i]
		lens.Material=if cached then Enum.Material.Neon else Enum.Material.SmoothPlastic
		lens.Size=Vector3.one*(if cached then Config.ActiveLensSize else Config.LensSize)
		if not cached then lens.Color=Color3.fromRGB(77,120,136); continue end
		local reading=cached.event
		local fade=math.min(1,cached.remaining/0.4)
		local proximity=reading.proximity
		if reading.kind=="tank" and reading.affiliation=="enemy" then
			lens.Color=Color3.fromRGB(77+(255-77)*fade,120+(160-145*proximity-120)*fade,136+(55-35*proximity-136)*fade)
			local noise=math.sin(renderer.sensorClock*91)+math.sin(renderer.sensorClock*137)*0.5
			local jolt=Config.MaxTremble*proximity^2*fade*noise
			lens.CFrame=lens.CFrame*CFrame.new(jolt,jolt*0.7,0)*CFrame.Angles(jolt,0,-jolt)
		elseif reading.kind=="tank" then lens.Color=Color3.fromRGB(77-27*fade,120+90*fade,136+94*fade)
		elseif reading.kind=="wall" then lens.Color=Color3.fromRGB(77+88*fade,120+49*fade,136+39*fade)
		else lens.Color=Color3.fromRGB(77+18*fade,120+(30+math.sin(renderer.sensorClock*15)*30)*fade,136+84*fade) end
	end
end
return Visual
