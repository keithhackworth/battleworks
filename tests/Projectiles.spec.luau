local Projectiles = require("ProjectileSimulation")
local Config = require("TankConfig")
local Targets = require("PracticeTargets")
local count = 0
local function check(ok, message) assert(ok,message); count += 1 end
local shooter, visuals = {}, {}
local origin, direction = Vector3.zero, Vector3.new(0,0,-1)
local world = { overlap = {}, object = nil, front = -24, side = 0, calls = 0 }
function world:GetPartBoundsInRadius(position,radius,params)
	check(radius == Config.ShellRadius and params.FilterDescendantsInstances[1] == shooter,
		"overlap checks use shell radius and exclude shooter")
	return self.overlap
end
function world:Spherecast(position,radius,delta,params)
	self.calls += 1
	check(params.FilterDescendantsInstances[1] == shooter and params.FilterDescendantsInstances[2] == visuals
		and params.RespectCanCollide == false, "sweep excludes shooter/visuals and respects queryable hitboxes")
	if self.object and math.abs(self.side) <= 4 + radius then
		local stop = self.front + radius
		if position.Z >= stop and position.Z + delta.Z <= stop then
			return { Instance = self.object, Position = Vector3.new(0,0,self.front), Distance = position.Z - stop }
		end
	end
	return nil
end
local function newShell() return Projectiles.new(origin,direction,{shooter,visuals}) end
local shell = newShell()
check(not shell.done and shell.position == origin, "launch does not resolve a hit or move instantly")
Projectiles.step(world,shell,0.5)
check(math.abs(shell.position.Z + 12) < 1e-5 and not shell.done, "shell travels twelve studs in half a second")
Projectiles.step(world,shell,0.5)
check(math.abs(shell.position.Z + 24) < 1e-5, "24 studs per second")
local targetPart = Instance.new("Part")
local target = Targets.new(targetPart)
world.object = targetPart
shell = newShell()
local hit = Projectiles.step(world,shell,0.5)
check(hit == nil and target.health == 100, "distant target takes no damage at launch or before arrival")
hit = Projectiles.step(world,shell,0.5)
check(hit and hit.Instance == targetPart and shell.done, "swept shell reaches target later")
Targets.impact(hit,{[targetPart]=target},1)
check(target.health == 75, "impact applies existing server target damage")
local calls = world.calls
check(Projectiles.step(world,shell,1) == nil and calls == world.calls, "consumed shell cannot hit twice")
-- Target moves sideways before the next sweep: no launch-time target lock.
shell = newShell(); world.side = 0
Projectiles.step(world,shell,0.5)
world.side = 20
check(Projectiles.step(world,shell,0.5) == nil and not shell.done and target.health == 75,
	"opponent can dodge before the shell arrives")
local wall = {}
world.side = 0; world.object = wall; world.front = -4
shell = newShell(); hit = Projectiles.step(world,shell,0.5)
check(hit.Instance == wall and shell.position.Z > -4 and shell.done, "sweep stops at cover without tunneling")
world.object = nil
shell = newShell()
Projectiles.step(world,shell,100)
check(shell.done and math.abs(shell.position.Magnitude - Config.Range) < 1e-5 and shell.remaining == 0,
	"range expiry caps travel even for oversized dt")
shell = newShell()
Projectiles.step(world,shell,0)
check(shell.position == origin and not shell.done, "zero dt does not move projectile")
local whole, halves = newShell(), newShell()
Projectiles.step(world,whole,1)
Projectiles.step(world,halves,0.5); Projectiles.step(world,halves,0.5)
check((whole.position-halves.position).Magnitude < 1e-5, "free-flight distance independent of step subdivision")
local pitched = Projectiles.new(origin,Vector3.new(0,1,-1),{shooter,visuals})
Projectiles.step(world,pitched,1)
check(math.abs(pitched.position.Magnitude - 24) < 1e-5 and pitched.position.Y > 0,
	"pitched shell preserves aim direction and total speed without gravity")
local box = { Size = Vector3.new(2,2,2), CFrame = { PointToObjectSpace = function(_,p) return p end } }
world.overlap = {box}
shell = newShell(); hit = Projectiles.step(world,shell,1/60)
check(hit.Instance == box and hit.Distance == 0 and shell.done, "initial overlap cannot evade spherecast")
box.CFrame.PointToObjectSpace = function() return Vector3.new(1.6,1.6,0) end
shell = newShell(); hit = Projectiles.step(world,shell,1/60)
check(hit == nil and not shell.done, "broadphase corner false positive rejected by sphere-box check")
world.overlap = {}
-- Shell starts at the cannon tip, but cannot skip cover inside barrel length.
world.object = nil
local launched, obstruction = Projectiles.launch(world,origin,direction,{shooter,visuals})
check(obstruction == nil and math.abs(launched.position.Z + Config.MuzzleOffset) < 1e-5,
	"unobstructed shell spawns seven studs forward at muzzle")
check(launched.remaining == Config.Range - Config.MuzzleOffset,"muzzle launch preserves original world range limit")
Projectiles.step(world,launched,0.5)
check(math.abs(launched.position.Z + Config.MuzzleOffset + 12)<1e-5,"muzzle-launched shell retains 24 studs per second")
world.object = wall; world.front = -4; world.side = 0
launched,obstruction = Projectiles.launch(world,origin,direction,{shooter,visuals})
check(obstruction and obstruction.Instance == wall and launched.done and launched.position.Z > -4,
	"barrel through wall resolves obstruction instead of spawning through cover")
world.object = nil
local pitchedLaunch = Projectiles.launch(world,origin,Vector3.new(0,1,-1),{shooter,visuals})
check(math.abs(pitchedLaunch.position.Magnitude-7)<1e-5 and pitchedLaunch.position.Y>0,
	"muzzle position follows authoritative pitch")
print(string.format("Projectile suite passed: %d assertions",count))

-- Windup must gate actual launch, not merely hide an already damaging shell.
do
	local Windup = require("WeaponWindup")
	local Simulation = require("TankSimulation")
	local state = Simulation.new(Vector3.zero)
	local pending = Windup.begin(state, {fire=true})
	assert(pending and state.cooldown == Config.Cooldown, "preparation reserves cooldown")
	for _ = 1,11 do
		local done, origin = Windup.step(pending,state,1/60)
		assert(not done and origin == nil, "no shell before 0.2 seconds")
	end
	state.position = Vector3.new(5,0,3); state.turretYaw = math.pi/2
	local done, origin, direction = Windup.step(pending,state,1/60)
	assert(done and (origin-(state.position+Vector3.new(0,3.6,0))).Magnitude<1e-5, "release uses current tank position")
	assert((direction-Simulation.forward(state.turretYaw,0)).Magnitude<1e-5, "release uses current aim")
	assert(Windup.begin(state,{fire=true}) == nil, "held fire cannot bypass cooldown")
	state.health=0
	local cancelled, deadOrigin = Windup.step({remaining=0.01},state,1)
	assert(cancelled and deadOrigin == nil, "death cancels a prepared shot")
	print("Weapon windup suite passed: release timing, current pose, cooldown and death cancellation")
end
