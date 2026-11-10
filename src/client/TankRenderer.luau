-- All animation is cosmetic. Anchored parts never participate in combat or physics.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local TerrainEffects = require(script.Parent.TerrainEffects)
local RattlerVisual = require(script.Parent.RattlerVisual)
local BarrelAnimation = require(script.Parent.BarrelAnimation)
local ScannerVisual = require(script.Parent.ScannerVisual)
local DamageVisual = require(script.Parent.DamageVisual)
local CombatVisual = require(script.Parent.TankCombatVisual)
local Config = require(game.ReplicatedStorage.Shared.TankConfig)
local Simulation = require(game.ReplicatedStorage.Shared.TankSimulation)
local Components = require(game.ReplicatedStorage.Shared.VehicleComponents)
local Renderer = {}
Renderer.__index = Renderer
local BARREL_DIAMETER = 1.6
local MUZZLE_DIAMETER = 1.8
local function part(parent, name, size, color)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color; p.Anchored = true
	p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
function Renderer.new(id, tankType, weaponId)
	local self = setmetatable({ recoil = 0, phase = 0, bounce = 0, bounceVelocity = 0, movement = 0, bounceClock = 0 }, Renderer)
	self.tankType = tankType or "Boomer"
 self.components=Components.forWeapon(self.tankType,weaponId)
 self.weapon=self.components.Weapon; self.weaponId=self.components.Installed.Weapon
 self.gatling=self.weapon.Visual.Kind=="Gatling"
 self.jackhammer=self.components.Recoil.Kind=="Jackhammer"
 self.inertial=self.components.Mobility.Motion=="Inertial" or self.jackhammer
 self.shotState={}; Components.bind(self.shotState,self.components)
	local rattler = self.tankType == "Rattler"
	self.model = Instance.new("Model"); self.model.Name = "Tank_" .. id; self.model.Parent = workspace
	self.model:SetAttribute("TankType",self.tankType)
	local orange = if rattler then Color3.fromRGB(25,144,62) else Color3.fromRGB(245, 116, 16)
	local deck = if rattler then Color3.fromRGB(99,190,44) else Color3.fromRGB(255, 147, 26)
	local yellow = if rattler then Color3.fromRGB(221,246,49) else Color3.fromRGB(255, 211, 27)
	local rubber = Color3.fromRGB(43, 49, 60)
	local steel = Color3.fromRGB(122, 132, 150)
	self.details = {}
	local function detail(name, size, color, anchor, offset, shape)
		local p = part(self.model, name, size, color)
		if shape then p.Shape = shape end
		table.insert(self.details, { part = p, anchor = anchor, offset = offset })
		return p
	end
	-- A solid rounded box: flat faces, twelve round edges and eight corner caps.
	-- All pieces share one anchor, so they move as a single cosmetic surface.
	local function rounded(name, size, radius, color, anchor, offset)
		local core = size - Vector3.one * (2 * radius)
		local face = detail(name, Vector3.new(core.X, core.Y, size.Z), color, anchor, offset)
		detail(name .. "FaceY", Vector3.new(size.X, core.Y, core.Z), color, anchor, offset)
		detail(name .. "FaceZ", Vector3.new(core.X, size.Y, core.Z), color, anchor, offset)
		for _, u in {-1, 1} do for _, v in {-1, 1} do
			detail(name .. "EdgeX", Vector3.new(core.X, radius*2, radius*2), color, anchor,
				offset * CFrame.new(0, u*core.Y/2, v*core.Z/2), Enum.PartType.Cylinder)
			detail(name .. "EdgeY", Vector3.new(core.Y, radius*2, radius*2), color, anchor,
				offset * CFrame.new(u*core.X/2, 0, v*core.Z/2) * CFrame.Angles(0, 0, math.pi/2), Enum.PartType.Cylinder)
			detail(name .. "EdgeZ", Vector3.new(core.Z, radius*2, radius*2), color, anchor,
				offset * CFrame.new(u*core.X/2, v*core.Y/2, 0) * CFrame.Angles(0, math.pi/2, 0), Enum.PartType.Cylinder)
			for _, w in {-1, 1} do
				detail(name .. "Corner", Vector3.one * radius*2, color, anchor,
					offset * CFrame.new(u*core.X/2, v*core.Y/2, w*core.Z/2), Enum.PartType.Ball)
			end
		end end
		face:SetAttribute("ArmorSize",size)
		return face
	end
	local colors={body=orange,deck=deck,steel=steel,dark=rubber}
	if rattler then
		RattlerVisual.buildBody(self,detail,rounded,colors)
	else
		self.chassis = rounded("Chassis", Vector3.new(6.6, 1.5, 7.6), 0.65, orange, "body", CFrame.new())
		rounded("Deck", Vector3.new(9, 0.6, 7.6), 0.28, deck, "body", CFrame.new(0, 0.75, 0.1))
		rounded("FrontArmor", Vector3.new(6, 0.6, 2.3), 0.28, orange, "body",
			CFrame.new(0, 0.55, -4) * CFrame.Angles(math.rad(-32), 0, 0))
		local front = CFrame.new(0, 0.55, -4) * CFrame.Angles(math.rad(-32), 0, 0)
		detail("FrontPanel", Vector3.new(2.5, 0.12, 1.1), rubber, "body", front * CFrame.new(0, 0.48, 0))
		for _, x in {-2.1, 2.1} do for _, z in {-0.65, 0.65} do
			detail("ArmorBolt", Vector3.new(0.34, 0.2, 0.34), steel, "body", front * CFrame.new(x, 0.4, z), Enum.PartType.Ball)
		end end
		-- Reference front plate: raised yellow border around its dark rectangular inset.
		detail("FrontPanelBorder", Vector3.new(3.3, 0.16, 1.8), yellow, "body", front * CFrame.new(0, 0.36, 0))
		-- Rear engine grille and fender seams fill the visible deck without cluttering the silhouette.
		detail("EngineGrille", Vector3.new(3.3, 0.1, 0.95), rubber, "body", CFrame.new(0, 0.91, 3.15))
		for i = 1, 8 do
			detail("EngineVent", Vector3.new(0.12, 0.08, 0.78), steel, "body", CFrame.new((i-4.5)*0.37, 1, 3.15))
		end
		for _, side in {-1, 1} do
			detail("FenderSeam", Vector3.new(0.08, 0.04, 5.8), Color3.fromRGB(213, 87, 9), "body", CFrame.new(side*2.95, 1.06, 0.25))
			for _, z in {-2.7, 2.8} do
				detail("DeckFastener", Vector3.new(0.22, 0.12, 0.22), steel, "body", CFrame.new(side*2.7, 1.08, z), Enum.PartType.Ball)
			end
			detail("RearLamp", Vector3.new(0.6, 0.3, 0.12), Color3.fromRGB(224, 57, 27), "body", CFrame.new(side*2.35, 0.2, 3.94))
			detail("TowMount", Vector3.new(0.45, 0.4, 0.25), steel, "body", front * CFrame.new(side*1.8, 0.3, 0.9))
		end
	end
	if rattler then
		RattlerVisual.buildTurret(self,detail,rounded,colors)
	else
		-- Short, wide molded-plastic turret; preserve the pivot and lower seating plane.
		self.turret = rounded("Turret", Vector3.new(6.5, 2.25, 5), 0.85, orange, "turret", CFrame.new(0, 0.375, 0.25))
		detail("TurretRing", Vector3.new(0.35, 4.1, 4.1), rubber, "turret", CFrame.new(0, -0.75, 0.25) * CFrame.Angles(0, 0, math.pi/2), Enum.PartType.Cylinder)
		detail("HatchBase", Vector3.new(0.22, 2, 2), Color3.fromRGB(229, 145, 9), "turret", CFrame.new(0.2, 1.57, 0.6) * CFrame.Angles(0, 0, math.pi/2), Enum.PartType.Cylinder)
		detail("CommanderHatch", Vector3.new(0.35, 1.7, 1.7), yellow, "turret", CFrame.new(0.2, 1.8, 0.6) * CFrame.Angles(0, 0, math.pi/2), Enum.PartType.Cylinder)
 end
 if self.gatling then
  RattlerVisual.build(self,detail,rounded,colors)
 else
		self.cannon = detail("Cannon", Vector3.new(6, BARREL_DIAMETER, BARREL_DIAMETER), steel, "barrel", CFrame.new(0, 0, -4) * CFrame.Angles(0, math.pi/2, 0), Enum.PartType.Cylinder)
		detail("Mantlet", Vector3.new(1, 2.1, 2.1), yellow, "barrel", CFrame.new(0, 0, -2) * CFrame.Angles(0, math.pi/2, 0), Enum.PartType.Cylinder)
		detail("BarrelCollar", Vector3.new(0.75, 1.95, 1.95), steel, "barrel", CFrame.new(0, 0, -2.65) * CFrame.Angles(0, math.pi/2, 0), Enum.PartType.Cylinder)
		for _, z in {-3.05, -6.85} do
			detail("BarrelBand", Vector3.new(0.16, MUZZLE_DIAMETER, MUZZLE_DIAMETER), rubber, "barrel", CFrame.new(0, 0, z) * CFrame.Angles(0, math.pi/2, 0), Enum.PartType.Cylinder)
		end
		detail("MuzzleBore", Vector3.new(0.025, 1.3, 1.3), Color3.fromRGB(16, 20, 24), "barrel", CFrame.new(0, 0, -7.015) * CFrame.Angles(0, math.pi/2, 0), Enum.PartType.Cylinder)
		-- Reusable parts swell along the barrel, then open the muzzle in a cartoon cough.
		self.barrelBulge = part(self.model, "BarrelBulge", Vector3.new(BARREL_DIAMETER, BARREL_DIAMETER, 2), steel)
		self.barrelBulge.Shape = Enum.PartType.Ball; self.barrelBulge.Transparency = 1
		self.muzzleSwell = part(self.model, "MuzzleSwell", Vector3.new(0.22, MUZZLE_DIAMETER, MUZZLE_DIAMETER), steel)
		self.muzzleSwell.Shape = Enum.PartType.Cylinder; self.muzzleSwell.Transparency = 1
		self.coughBore = part(self.model, "CoughBore", Vector3.new(0.03, 1.3, 1.3), rubber)
		self.coughBore.Shape = Enum.PartType.Cylinder; self.coughBore.Transparency = 1
	end
	self.treads={}
	if self.components.Mobility.Kind=="Wheeled" then
		RattlerVisual.buildWheels(self,detail,colors)
	else
		self.left = part(self.model, "LeftTrack", Vector3.new(1.7, 2.4, 9), rubber)
		self.right = part(self.model, "RightTrack", self.left.Size, rubber)
		-- Hide the square track cores behind the rounded, circulating belt geometry.
		self.left.Size = Vector3.new(1.7, 2.2, 6.6); self.right.Size = self.left.Size
		for _, side in {-1, 1} do
			for _, z in {-3.3, 3.3} do
				detail("TrackEnd", Vector3.new(1.7, 2.4, 2.4), rubber, "base", CFrame.new(side*3.8, 1.4, z), Enum.PartType.Cylinder)
			end
			for i = 1, 4 do
				local z = (i - 2.5)*2.08
				detail("RoadWheel", Vector3.new(0.18, 1.85, 1.85), steel, "base", CFrame.new(side*4.68, 1.4, z), Enum.PartType.Cylinder)
				detail("WheelHub", Vector3.new(0.22, 1.05, 1.05), rubber, "base", CFrame.new(side*4.72, 1.4, z), Enum.PartType.Cylinder)
				detail("Axle", Vector3.new(0.25, 0.4, 0.4), steel, "base", CFrame.new(side*4.75, 1.4, z), Enum.PartType.Cylinder)
			end
			for i = 1, 6 do
				detail("DeckRib", Vector3.new(1.3, 0.22, 0.4), yellow, "body", CFrame.new(side*3.6, 1.16, (i-3.5)*1.05))
			end
			detail("FrontLight", Vector3.new(1.3, 0.16, 0.4), yellow, "body", CFrame.new(side*3.5, 1.08, -3.1))
			detail("CheekMount", Vector3.new(0.3, 1.2, 1.2), yellow, "turret", CFrame.new(side*3.17, -0.05, -1.25), Enum.PartType.Cylinder)
			detail("CheekInset", Vector3.new(0.34, 0.9, 0.9), rubber, "turret", CFrame.new(side*3.3, -0.05, -1.25), Enum.PartType.Cylinder)
			detail("CheekButton", Vector3.new(0.36, 0.48, 0.48), yellow, "turret", CFrame.new(side*3.35, -0.05, -1.25), Enum.PartType.Cylinder)
			for i = 1, 3 do
				detail("TurretStripe", Vector3.new(0.035, 0.65, 0.28), yellow, "turret", CFrame.new(side*3.265, 0.375, (i-2)*0.48+0.35) * CFrame.Angles(math.rad(-15), 0, 0))
			end
		end
		self.treads = {}
		for side = -1, 1, 2 do
			for index = 1, 28 do
				local p = part(self.model, "TrackShoe", Vector3.new(1.85, 0.18, 0.62), Color3.fromRGB(72, 82, 100))
				table.insert(self.treads, { part = p, side = side, index = index })
			end
		end
	end
	ScannerVisual.build(self,detail)
	CombatVisual.attach(self)
	return self
end
function Renderer:fire(rock)
	if self.gatling then self.recoil=self.weapon.Visual.Recoil; RattlerVisual.jolt(self,rock); return end
	self.recoil = self.weapon.Visual.Recoil
	self.shotAge = if self.weapon.Visual.Swelling then 0 else nil
end
function Renderer:resetPose(state)
	self.position = state.position; self.yaw = state.yaw
	self.turretYaw, self.turretPitch = Simulation.turretAngles(state)
	self.recoil = 0; self.shotAge = nil
	self.terrainEffectAge=0; self.lastSurface=nil
	self.landingSerial=state.landingSerial or 0
	self.rockSerial=state.flightShotSerial or 0; self.visualRollKick=0; self.rockHold=0
	self.bodyPitch = state.bodyPitch or 0; self.bodyRoll = state.bodyRoll or 0
	self.bounce = state.bounce or 0; self.bounceVelocity = 0; self.movement = 0; self.bounceClock = 0
	if not self.gatling then
		self.cannon.Size = Vector3.new(6, BARREL_DIAMETER, BARREL_DIAMETER)
		self.barrelBulge.Transparency = 1; self.muzzleSwell.Transparency = 1; self.coughBore.Transparency = 1
	end
end
function Renderer:update(state, dt)
	local alpha = 1 - math.exp(-18 * dt)
	local previousPosition=self.position
	self.position = if self.position then self.position:Lerp(state.position, alpha) else state.position
	local landed=(state.landingSerial or 0)>(self.landingSerial or 0)
	if self.inertial and previousPosition then
		local y=if landed then state.position.Y else previousPosition.Y+(state.position.Y-previousPosition.Y)*(1-math.exp(-60*dt))
		self.position=Vector3.new(self.position.X,y,self.position.Z)
	end
	local function smoothAngle(current, target)
		if not current then return target end
		return current + math.atan2(math.sin(target - current), math.cos(target - current)) * alpha
	end
	self.yaw = smoothAngle(self.yaw, state.yaw)
	local actualYaw,actualPitch = Simulation.turretAngles(state)
	self.turretYaw = smoothAngle(self.turretYaw, actualYaw)
	self.turretPitch = smoothAngle(self.turretPitch, actualPitch or 0)
	self.phase += dt * math.abs(state.speed) * 0.7
	self.recoil *= math.exp(-12 * dt)
	if self.shotAge then self.shotAge += math.max(dt, 0) end
	local swelling = BarrelAnimation.sample(self.shotAge)
	if not swelling.active or state.health <= 0 then self.shotAge = nil; swelling = BarrelAnimation.sample(nil) end
	if not self.gatling then
		self.cannon.Size = Vector3.new(6, BARREL_DIAMETER*swelling.barrelScale, BARREL_DIAMETER*swelling.barrelScale)
	end
	-- Suspension is server-owned because the tilted barrel now controls shots.
	local suspensionAlpha=if self.inertial then 1-math.exp(-50*dt) else alpha
	self.bounce += ((state.bounce or 0)-self.bounce)*suspensionAlpha
	self.bodyPitch = (self.bodyPitch or 0)+((state.bodyPitch or 0)-(self.bodyPitch or 0))*suspensionAlpha
	self.bodyRoll = (self.bodyRoll or 0)+((state.bodyRoll or 0)-(self.bodyRoll or 0))*suspensionAlpha
	local base = CFrame.new(self.position) * CFrame.Angles(0, self.yaw, 0)
	local body = base * CFrame.new(0, 2.1+self.bounce, 0) * CFrame.Angles(self.bodyPitch, 0, self.bodyRoll)
	local turret = CFrame.new(self.position + Vector3.new(0, Config.MuzzleHeight+self.bounce, 0)) * CFrame.Angles(0, self.yaw, 0) * CFrame.Angles(self.bodyPitch, 0, self.bodyRoll) * CFrame.Angles(0, self.turretYaw-self.yaw, 0)
	if self.components.Mobility.Motion=="Inertial" or self.jackhammer then
		local pivotHeight=Config.MuzzleHeight+self.bounce
		local roll=if self.jackhammer then RattlerVisual.rock(self,state,dt) else self.bodyRoll
		-- One common pose for wheels, hull and turret, rocking about the weapon
		-- mount so presentation cannot move the authoritative muzzle origin.
		base=base*CFrame.new(0,pivotHeight,0)*CFrame.Angles(self.bodyPitch,0,roll)*CFrame.new(0,-pivotHeight,0)
		body=base*CFrame.new(0,2.1+self.bounce,0)
		turret=base*CFrame.new(0,pivotHeight,0)*CFrame.Angles(0,self.turretYaw-self.yaw,0)
	end
	if self.left then
		self.left.CFrame = base * CFrame.new(-3.8, 1.4, 0)
		self.right.CFrame = base * CFrame.new(3.8, 1.4, 0)
	end
	local barrel = turret * CFrame.Angles(self.turretPitch, 0, 0) * CFrame.new(0, 0, self.recoil * 0.8)
 if self.weapon.Trajectory then
  local pose=self.shotState
  pose.position=self.position; pose.yaw=self.yaw; pose.turretYaw=self.turretYaw; pose.turretPitch=self.turretPitch
  pose.bodyPitch=self.bodyPitch; pose.bodyRoll=self.bodyRoll; pose.bounce=self.bounce; pose.groundPlaneY=state.groundPlaneY
  local pivot,direction=Simulation.shotPose(pose)
  barrel=CFrame.lookAt(pivot,pivot+direction,turret.UpVector)*CFrame.new(0,0,self.recoil*0.8)
 end
	self.muzzleFrame = barrel*CFrame.new(0,0,-7)
	local spin=if self.gatling then RattlerVisual.spin(self,state,dt) else 0
	local anchors = { body = body, base = base, turret = turret, barrel = barrel, rotor = barrel*CFrame.Angles(0,0,spin) }
	if self.wheels then RattlerVisual.wheelFrames(self,state,dt,base,anchors) end
	for _, item in self.details do item.part.CFrame = anchors[item.anchor] * item.offset end
	if not self.gatling then
		self.barrelBulge.Size = Vector3.new(swelling.bulge, swelling.bulge, 2.6)
		self.barrelBulge.CFrame = barrel * CFrame.new(0, 0, swelling.z)
		local mouth = MUZZLE_DIAMETER + swelling.flare*1.8
		self.muzzleSwell.Size = Vector3.new(0.3, mouth, mouth)
		self.muzzleSwell.CFrame = barrel * CFrame.new(0, 0, -6.95) * CFrame.Angles(0, math.pi/2, 0)
		self.coughBore.Size = Vector3.new(0.035, mouth*0.72, mouth*0.72)
		self.coughBore.CFrame = barrel * CFrame.new(0, 0, -7.12) * CFrame.Angles(0, math.pi/2, 0)
	end
	local radius, straight = 1.2, 6.6
	local arc = math.pi * radius
	local perimeter = 2 * straight + 2 * arc
	for _, tread in self.treads do
		local t = ((tread.index-1)*perimeter/28 + self.phase*math.sign(state.speed)) % perimeter
		local y, z, angle
		if t < straight then
			y, z, angle = radius, -straight/2+t, 0
		elseif t < straight+arc then
			local a = (t-straight)/radius
			y, z, angle = radius*math.cos(a), straight/2+radius*math.sin(a), a
		elseif t < 2*straight+arc then
			y, z, angle = -radius, straight/2-(t-straight-arc), math.pi
		else
			local a = (t-2*straight-arc)/radius
			y, z, angle = -radius*math.cos(a), -straight/2-radius*math.sin(a), math.pi+a
		end
		tread.part.CFrame = base * CFrame.new(tread.side*3.8, 1.4+y, z) * CFrame.Angles(angle, 0, 0)
	end
	for _, p in self.model:GetChildren() do
		if p:IsA("BasePart") or p:IsA("Part") then p.Transparency = if state.health <= 0 then 0.35 else 0 end
	end
	if not self.gatling then
		self.barrelBulge.Transparency = if swelling.active then 1-swelling.opacity else 1
		self.muzzleSwell.Transparency = if swelling.active then 1-swelling.flare else 1
		self.coughBore.Transparency = if swelling.active then 1-swelling.flare else 1
	end
	if landed and self.jackhammer and state.health>0 then
		RattlerVisual.landing(state.position,part)
	end
	self.landingSerial=state.landingSerial or 0
	DamageVisual.update(self,state,dt,part)
	CombatVisual.update(self,state,part,anchors,dt)
	DamageVisual.poseMarks(self)
	ScannerVisual.update(self,state,dt)
	TerrainEffects.update(self,state,dt)
end
function Renderer:destroy() self.model:Destroy() end
-- Exaggerated cosmetic burst readable from the normal battlefield camera; no Explosion/force or damage is involved.
function Renderer.shot(origin, direction, tankType, weaponId)
	if Components.forWeapon(tankType or "Boomer",weaponId).Weapon.Visual.Kind=="Gatling" then RattlerVisual.shot(origin,direction,part); return end
	direction = direction or Vector3.new(0, 0, -1)
	local frame = CFrame.lookAt(origin, origin + direction)
	local center = origin - direction*0.2
	local flash = part(workspace, "MuzzleFlash", Vector3.new(3.2, 3.2, 3.2), Color3.fromRGB(255, 240, 150))
	flash.Shape = Enum.PartType.Ball; flash.Material = Enum.Material.Neon; flash.Position = center; flash.CastShadow = false
	TweenService:Create(flash, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.05), { Size = Vector3.new(5.5,5.5,5.5), Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.35)
	for index = 1, 12 do
		local angle = (index-1)*math.pi/6
		local radial = frame.RightVector*math.cos(angle) + frame.UpVector*math.sin(angle)
		local spark = part(workspace, "MuzzleSpark", Vector3.new(0.55,0.55,2.2),
			if index%2 == 0 then Color3.fromRGB(255,176,32) else Color3.fromRGB(255,238,137))
		spark.Material = Enum.Material.Neon; spark.CastShadow = false
		spark.CFrame = CFrame.lookAt(center+radial*1.1, center+radial*2.1)
		local endpoint = center + radial*(if index%2 == 0 then 4.2 else 5.5) + direction*0.15
		TweenService:Create(spark, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.04), {
			CFrame = CFrame.lookAt(endpoint, endpoint+radial), Size = Vector3.new(0.18,0.18,0.75), Transparency = 1,
		}):Play()
		Debris:AddItem(spark, 0.42)
	end
end
return Renderer
