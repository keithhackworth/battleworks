-- Rattler's reference-inspired model/weapon cosmetics; shared renderer owns movement.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Visual = {}
function Visual.buildBody(self,detail,rounded,colors)
	local green,lime,dark=colors.body,colors.deck,colors.dark
	local ivory=Color3.fromRGB(239,239,186)
	self.chassis=rounded("Chassis",Vector3.new(5.9,1.25,7.3),0.55,green,"body",CFrame.new(0,-0.15,0))
	local hood=CFrame.new(0,0.65,-1.15)*CFrame.Angles(math.rad(-18),0,0)
	rounded("RattlerSlopingHood",Vector3.new(5.6,0.75,4.8),0.35,lime,"body",hood)
	rounded("IvoryHoodBorder",Vector3.new(3.2,0.18,3.6),0.08,ivory,"body",hood*CFrame.new(0,0.46,0))
	for _,z in {-0.85,0.85} do
		detail("HoodPanel",Vector3.new(2.5,0.1,1.25),colors.steel,"body",hood*CFrame.new(0,0.58,z))
	end
	rounded("RattlerNeck",Vector3.new(3.2,1.45,2.4),0.5,green,"body",CFrame.new(0,0.9,1.25))
	detail("FrontBumper",Vector3.new(4.8,0.6,0.55),dark,"body",CFrame.new(0,-0.2,-3.9))
	for _,side in {-1,1} do
		detail("Headlight",Vector3.new(0.9,0.12,0.5),Color3.fromRGB(239,255,74),"body",hood*CFrame.new(side*2,0.45,-1.65))
		detail("RearTailLight",Vector3.new(0.5,0.35,0.12),Color3.fromRGB(241,82,35),"body",CFrame.new(side*2,0.15,3.7))
		for _,axle in {-1,1} do
			detail("RoundedFender",Vector3.new(2.1,0.75,3.3),green,"body",CFrame.new(side*3.45,0.65,axle*2.6),Enum.PartType.Ball)
		end
	end
end
function Visual.buildWheels(self,detail,colors)
	self.wheels={}; self.wheelSpin=0; self.steeringAngle=0
	for _,side in {-1,1} do for _,axle in {-1,1} do
		local key="wheel"..side.."_"..axle
		table.insert(self.wheels,{key=key,side=side,axle=axle})
		detail("ChunkyTire",Vector3.new(1.9,2.7,2.7),colors.dark,key,CFrame.new(),Enum.PartType.Ball)
		detail("RoadWheel",Vector3.new(0.24,1.8,1.8),colors.steel,key,CFrame.new(side*0.93,0,0),Enum.PartType.Cylinder)
		detail("WheelGreenHub",Vector3.new(0.28,1.25,1.25),colors.body,key,CFrame.new(side*1.02,0,0),Enum.PartType.Cylinder)
		detail("WheelYellowHub",Vector3.new(0.32,0.5,0.5),Color3.fromRGB(234,247,63),key,CFrame.new(side*1.08,0,0),Enum.PartType.Cylinder)
		for index=1,12 do
			local angle=(index-1)*math.pi/6
			detail("TireLug",Vector3.new(1.6,0.18,0.45),Color3.fromRGB(64,71,77),key,
				CFrame.new(0,math.cos(angle)*1.3,math.sin(angle)*1.3)*CFrame.Angles(angle,0,0))
		end
		for index=1,3 do
			local a=(index-1)*math.pi*2/3
			detail("WheelSpoke",Vector3.new(0.3,0.2,0.2),Color3.fromRGB(177,196,185),key,CFrame.new(side*1.08,math.cos(a)*0.62,math.sin(a)*0.62),Enum.PartType.Ball)
		end
	end end
end
function Visual.wheelFrames(self,state,dt,base,anchors)
	self.wheelSpin=(self.wheelSpin-state.speed*dt/1.35)%(math.pi*2)
	self.steeringAngle += ((state.steeringAngle or 0)-self.steeringAngle)*(1-math.exp(-18*dt))
	for _,wheel in self.wheels do
		anchors[wheel.key]=base*CFrame.new(wheel.side*3.45,1.35,wheel.axle*2.6)
			*CFrame.Angles(0,if wheel.axle<0 then self.steeringAngle else 0,0)*CFrame.Angles(self.wheelSpin,0,0)
	end
end
function Visual.buildTurret(self,detail,rounded,colors)
	self.turret = rounded("Turret",Vector3.new(4.9,1.8,4.1),0.65,colors.body,"turret",CFrame.new(0,0.25,0.35))
 detail("TopLatch",Vector3.new(0.7,0.4,0.9),colors.steel,"turret",CFrame.new(0,1.32,0.5)*CFrame.Angles(math.rad(-12),0,0))
 detail("RearBattery",Vector3.new(2.1,0.8,0.7),colors.dark,"turret",CFrame.new(0,0.05,2.35))
end
function Visual.build(self, detail, rounded, colors)
	local green,lime,steel,dark = colors.body,colors.deck,colors.steel,colors.dark
	local ivory = Color3.fromRGB(239,239,186)

	rounded("GatlingHousing",Vector3.new(3.3,2.25,2.4),0.75,lime,"barrel",CFrame.new(0,0,-1.7))
	detail("RotorBearing",Vector3.new(0.5,2.5,2.5),steel,"barrel",CFrame.new(0,0,-2.8)*CFrame.Angles(0,math.pi/2,0),Enum.PartType.Cylinder)
	for _,side in {-1,1} do
		detail("AmmoDrum",Vector3.new(0.85,1.9,1.9),steel,"turret",CFrame.new(side*2.65,0.1,0.2),Enum.PartType.Cylinder)
		detail("AmmoDrumCap",Vector3.new(0.92,1.35,1.35),ivory,"turret",CFrame.new(side*2.7,0.1,0.2),Enum.PartType.Cylinder)
		detail("DrumHub",Vector3.new(0.95,0.55,0.55),dark,"turret",CFrame.new(side*2.75,0.1,0.2),Enum.PartType.Cylinder)
	end
	self.cannon = detail("GatlingCore",Vector3.new(4.4,0.5,0.5),dark,"rotor",CFrame.new(0,0,-4.8)*CFrame.Angles(0,math.pi/2,0),Enum.PartType.Cylinder)
	for index=1,6 do
		local angle=(index-1)*math.pi/3
		local x,y=math.cos(angle)*0.76,math.sin(angle)*0.76
		detail("GatlingBarrel",Vector3.new(4.4,0.49,0.49),steel,"rotor",CFrame.new(x,y,-4.8)*CFrame.Angles(0,math.pi/2,0),Enum.PartType.Cylinder)
		detail("GatlingMuzzle",Vector3.new(0.23,0.57,0.57),steel,"rotor",CFrame.new(x,y,-6.95)*CFrame.Angles(0,math.pi/2,0),Enum.PartType.Cylinder)
		detail("GatlingBore",Vector3.new(0.025,0.34,0.34),dark,"rotor",CFrame.new(x,y,-7.075)*CFrame.Angles(0,math.pi/2,0),Enum.PartType.Cylinder)
	end
	for _,z in {-3.4,-6.45} do
		detail("RotorBrace",Vector3.new(0.3,2.2,2.2),dark,"rotor",CFrame.new(0,0,z)*CFrame.Angles(0,math.pi/2,0),Enum.PartType.Cylinder)
		for i=1,3 do
			local angle=(i-1)*math.pi*2/3
			detail("RotorBraceBolt",Vector3.new(0.34,0.18,0.18),lime,"rotor",CFrame.new(math.cos(angle)*0.93,math.sin(angle)*0.93,z-0.02)*CFrame.Angles(0,math.pi/2,0),Enum.PartType.Cylinder)
		end
	end
	self.rotorAngle=0; self.rotorSpeed=0
end
function Visual.jolt(self,event)
	if not event or (event.serial or 0)<=(self.rockSerial or 0) then return end
	self.rockSerial=event.serial
	self.visualRollKick=(event.roll or 0)*1.8
	self.rockHold=0.035
end
function Visual.rock(self,state,dt)
	-- Shot delivery preserves the full impulse instead of waiting for a decayed
	-- 20 Hz snapshot. A snapshot is also a fallback if the model was just built.
	Visual.jolt(self,{serial=state.flightShotSerial,roll=state.flightRoll})
	if (self.rockHold or 0)>0 then self.rockHold=math.max(0,self.rockHold-dt)
	else self.visualRollKick=(self.visualRollKick or 0)*math.exp(-7*dt) end
	local groundRoll=state.groundRoll or ((state.bodyRoll or 0)-(state.flightRoll or 0))
	local roll=groundRoll+(self.visualRollKick or 0)
	-- Do not bury a grounded tire to exaggerate a hop. Full lurch is available
	-- immediately after lift-off, while the simulation position stays unchanged.
	local clearance=math.max(0,self.position.Y-(state.groundHeight or state.groundPlaneY or 0))
	local limit=math.min(math.rad(24),math.atan2(clearance+0.1,4.3))
	return math.clamp(roll,-limit,limit)
end
function Visual.spin(self,state,dt)
	local target=if state.firing and state.health>0 then 22 else 0
	self.rotorSpeed += (target-self.rotorSpeed)*(1-math.exp(-14*dt))
	self.rotorAngle = (self.rotorAngle+self.rotorSpeed*dt)%(math.pi*2)
	return self.rotorAngle
end
local function sound(parent,id,volume,pitch)
	local s=Instance.new("Sound"); s.SoundId=id; s.Volume=volume; s.PlaybackSpeed=pitch
	s.RollOffMinDistance=12; s.RollOffMaxDistance=160; s.Parent=parent
	s:Play(); Debris:AddItem(s,0.8)
end
function Visual.shot(origin,direction,makePart)
	local frame=CFrame.lookAt(origin,origin+direction)
	local flash=makePart(workspace,"RattlerFlash",Vector3.new(2.2,2.2,2.2),Color3.fromRGB(246,255,125))
	flash.Shape=Enum.PartType.Ball; flash.Material=Enum.Material.Neon; flash.Position=origin-direction*0.2; flash.CastShadow=false
	TweenService:Create(flash,TweenInfo.new(0.13),{Size=Vector3.new(4.1,4.1,4.1),Transparency=1}):Play()
	-- Built-in local assets need no uploaded sound or third-party asset permissions.
	sound(flash,"rbxasset://sounds/electronicpingshort.wav",0.65,0.65+math.random()*0.25)
	sound(flash,"rbxasset://sounds/action_jump_land.mp3",0.45,1.8)
	Debris:AddItem(flash,0.8)
	for i=1,4 do
		local angle=(i-1)*math.pi/2+math.random()*0.3
		local radial=frame.RightVector*math.cos(angle)+frame.UpVector*math.sin(angle)
		local spark=makePart(workspace,"RattlerSpark",Vector3.new(0.4,0.4,1.5),Color3.fromRGB(255,211,57))
		spark.Material=Enum.Material.Neon; spark.CastShadow=false
		spark.CFrame=CFrame.lookAt(origin+radial*0.6,origin+radial*1.6)
		local endpoint=origin+radial*3
		TweenService:Create(spark,TweenInfo.new(0.15),{CFrame=CFrame.lookAt(endpoint,endpoint+radial),Transparency=1}):Play()
		Debris:AddItem(spark,0.2)
	end
	local puff=makePart(workspace,"RattlerSmoke",Vector3.new(1,1,1),Color3.fromRGB(169,178,153))
	puff.Shape=Enum.PartType.Ball; puff.Transparency=0.5; puff.Position=origin; puff.CastShadow=false
	TweenService:Create(puff,TweenInfo.new(0.45),{Position=origin+Vector3.new(0,2,0)-direction,Size=Vector3.new(3,3,3),Transparency=1}):Play()
	Debris:AddItem(puff,0.5)
	local casing=makePart(workspace,"RattlerCasing",Vector3.new(0.25,0.25,0.65),Color3.fromRGB(236,185,51))
	casing.CFrame=frame*CFrame.new(1,0,2.5)
	TweenService:Create(casing,TweenInfo.new(0.35),{CFrame=frame*CFrame.new(3,-2,3)*CFrame.Angles(1,2,1),Transparency=1}):Play()
	Debris:AddItem(casing,0.4)
end
function Visual.landing(position,makePart)
	local center=Vector3.new(position.X,position.Y+0.25,position.Z)
	for i=1,8 do
		local a=(i-1)*math.pi/4
		local radial=Vector3.new(math.cos(a),0,math.sin(a))
		local puff=makePart(workspace,"RattlerLandingDust",Vector3.new(2,1.2,2),Color3.fromRGB(180,164,125))
		puff.Shape=Enum.PartType.Ball; puff.Transparency=0.25; puff.CastShadow=false
		puff.Position=center+radial*2
		TweenService:Create(puff,TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{
			Position=center+radial*6,Size=Vector3.new(4,0.7,4),Transparency=1,
		}):Play()
		if i==1 then sound(puff,"rbxasset://sounds/action_jump_land.mp3",1.2,0.55) end
		Debris:AddItem(puff,0.8)
	end
end
return Visual
