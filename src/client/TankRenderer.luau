-- All animation is cosmetic. Anchored parts never participate in combat or physics.
local Debris = game:GetService("Debris")
local Renderer = {}
Renderer.__index = Renderer
local function part(parent, name, size, color)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.Color = color; p.Anchored = true
	p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
	p.Material = Enum.Material.Metal; p.Parent = parent
	return p
end
function Renderer.new(id)
	local self = setmetatable({ recoil = 0, phase = 0 }, Renderer)
	self.model = Instance.new("Model"); self.model.Name = "Tank_" .. id; self.model.Parent = workspace
	self.chassis = part(self.model, "Chassis", Vector3.new(6, 2, 8), Color3.fromRGB(93, 122, 76))
	self.left = part(self.model, "LeftTrack", Vector3.new(1.7, 2.4, 9), Color3.fromRGB(36, 40, 43))
	self.right = part(self.model, "RightTrack", self.left.Size, self.left.Color)
	self.turret = part(self.model, "Turret", Vector3.new(4.5, 1.7, 4.5), Color3.fromRGB(115, 145, 87))
	self.cannon = part(self.model, "Cannon", Vector3.new(0.65, 0.65, 6), Color3.fromRGB(65, 78, 57))
	self.treads = {}
	for side = -1, 1, 2 do
		for index = 1, 7 do
			local p = part(self.model, "TrackShoe", Vector3.new(1.85, 0.15, 0.65), Color3.fromRGB(72, 77, 80))
			table.insert(self.treads, { part = p, side = side, index = index })
		end
	end
	return self
end
function Renderer:update(state, dt)
	local alpha = 1 - math.exp(-18 * dt)
	self.position = if self.position then self.position:Lerp(state.position, alpha) else state.position
	local function smoothAngle(current, target)
		if not current then return target end
		return current + math.atan2(math.sin(target - current), math.cos(target - current)) * alpha
	end
	self.yaw = smoothAngle(self.yaw, state.yaw)
	self.turretYaw = smoothAngle(self.turretYaw, state.turretYaw)
	self.turretPitch = smoothAngle(self.turretPitch, state.turretPitch or 0)
	self.phase += dt * math.abs(state.speed) * 0.7
	self.recoil *= math.exp(-12 * dt)
	local wobble = math.sin(self.phase * 2) * math.min(math.abs(state.speed) / 24, 1) * 0.025
	local base = CFrame.new(self.position) * CFrame.Angles(0, self.yaw, 0)
	local body = base * CFrame.new(0, 2.1, 0) * CFrame.Angles(wobble + self.recoil * 0.04, 0, wobble * 0.5)
	self.chassis.CFrame = body
	self.left.CFrame = base * CFrame.new(-3.8, 1.4, 0)
	self.right.CFrame = base * CFrame.new(3.8, 1.4, 0)
	local turret = CFrame.new(self.position + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, self.turretYaw, 0)
	self.turret.CFrame = turret
	self.cannon.CFrame = turret * CFrame.Angles(self.turretPitch, 0, 0) * CFrame.new(0, 0, -4 + self.recoil * 0.8)
	for _, tread in self.treads do
		local z = ((tread.index * 1.2 + self.phase * math.sign(state.speed)) % 8.4) - 4.2
		tread.part.CFrame = base * CFrame.new(tread.side * 3.8, 2.65, z)
	end
	for _, p in self.model:GetChildren() do
		p.Transparency = if state.health <= 0 then 0.7 else 0
	end
end
function Renderer:destroy() self.model:Destroy() end
function Renderer.shot(origin, endpoint)
	local delta = endpoint - origin
	if delta.Magnitude < 0.01 then return end
	local tracer = part(workspace, "Tracer", Vector3.new(0.15, 0.15, delta.Magnitude), Color3.fromRGB(255, 218, 99))
	tracer.Material = Enum.Material.Neon
	tracer.CFrame = CFrame.lookAt((origin + endpoint) / 2, endpoint)
	Debris:AddItem(tracer, 0.07)
	local flash = part(workspace, "MuzzleFlash", Vector3.new(1.4, 1.4, 1.4), tracer.Color)
	flash.Shape = Enum.PartType.Ball; flash.Material = Enum.Material.Neon; flash.Position = origin
	Debris:AddItem(flash, 0.06)
end
return Renderer
